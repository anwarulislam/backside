import AppKit
import QuartzCore
import ApplicationServices

@MainActor
final class ScratchpadPanel: NSPanel, NSTextViewDelegate {
    let target: TargetWindow
    var onDismiss: ((String) -> Void)?

    private let noteStore: NoteStore
    private let cardMargin: CGFloat = 24

    private let containerView = FlipHostContainerView()
    private let flipHostView = NSView()
    private let frontCard = FrontWindowCardView()
    private let backCard = BacksideCardView()

    private var visibleAsBackside = false
    private var isAnimating = false
    private(set) var isInvalid = false
    private var hideMethod: TargetWindowHidingService.HideMethod = .none

    init(target: TargetWindow, noteStore: NoteStore) {
        self.target = target
        self.noteStore = noteStore
        noteStore.register(target)

        let targetRect = Self.appKitFrame(for: target.frame() ?? .zero)
        let panelFrame = targetRect.insetBy(dx: -cardMargin, dy: -cardMargin)

        super.init(
            contentRect: panelFrame,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        titleVisibility = .hidden
        animationBehavior = .none

        setupViews()
    }

    deinit {
        TargetWindowHidingService.restore(method: hideMethod, pid: target.pid)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    private func setupViews() {
        containerView.wantsLayer = true
        var perspective = CATransform3DIdentity
        perspective.m34 = -1.0 / 1200.0
        containerView.layer?.sublayerTransform = perspective
        containerView.cardView = flipHostView
        self.contentView = containerView

        flipHostView.wantsLayer = true
        flipHostView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(flipHostView)

        NSLayoutConstraint.activate([
            flipHostView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: cardMargin),
            flipHostView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -cardMargin),
            flipHostView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: cardMargin),
            flipHostView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -cardMargin)
        ])

        frontCard.translatesAutoresizingMaskIntoConstraints = false
        backCard.translatesAutoresizingMaskIntoConstraints = false

        flipHostView.addSubview(frontCard)
        flipHostView.addSubview(backCard)

        NSLayoutConstraint.activate([
            frontCard.leadingAnchor.constraint(equalTo: flipHostView.leadingAnchor),
            frontCard.trailingAnchor.constraint(equalTo: flipHostView.trailingAnchor),
            frontCard.topAnchor.constraint(equalTo: flipHostView.topAnchor),
            frontCard.bottomAnchor.constraint(equalTo: flipHostView.bottomAnchor),

            backCard.leadingAnchor.constraint(equalTo: flipHostView.leadingAnchor),
            backCard.trailingAnchor.constraint(equalTo: flipHostView.trailingAnchor),
            backCard.topAnchor.constraint(equalTo: flipHostView.topAnchor),
            backCard.bottomAnchor.constraint(equalTo: flipHostView.bottomAnchor)
        ])

        let savedNote = noteStore.note(for: target.key)
        backCard.editor.string = savedNote
        backCard.editor.delegate = self
        backCard.update(target: target)
        backCard.updatePlaceholder(isEmpty: savedNote.isEmpty)
        backCard.onFlipBack = { [weak self] in
            self?.hide(animated: true)
        }

        frontCard.update(target: target, snapshot: nil)
        frontCard.isHidden = true
    }

    func reveal() {
        guard !isAnimating else { return }
        guard let axFrame = target.frame() else { invalidate(); return }

        let targetRect = Self.appKitFrame(for: axFrame)
        setFrame(targetRect.insetBy(dx: -cardMargin, dy: -cardMargin), display: true)

        // Capture live target window snapshot BEFORE moving the window offscreen
        let snapshot = WindowSnapshotService.capture(windowNumber: target.windowNumber, screenRect: axFrame)
        frontCard.update(target: target, snapshot: snapshot)
        backCard.update(target: target)
        let savedNote = noteStore.note(for: target.key)
        backCard.editor.string = savedNote
        backCard.updatePlaceholder(isEmpty: savedNote.isEmpty)

        containerView.layoutSubtreeIfNeeded()
        prepareLayersForAnimation()

        isAnimating = true
        visibleAsBackside = true
        alphaValue = 1.0

        frontCard.isHidden = false
        backCard.isHidden = false

        // Intelligently hide the target window without switching frontmost app
        hideMethod = TargetWindowHidingService.hideWindow(for: target)

        makeKeyAndOrderFront(nil)
        makeFirstResponder(backCard.editor)

        let duration: CFTimeInterval = 0.40
        let timing = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1.0)
        let depth = min(180, max(90, flipHostView.bounds.width * 0.18))

        let frontTransforms = Self.makeFlipKeyframes(fromAngle: 0, toAngle: .pi, maxDepth: depth)
        let backTransforms = Self.makeFlipKeyframes(fromAngle: -.pi, toAngle: 0, maxDepth: depth)

        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(timing)
        CATransaction.setCompletionBlock { [weak self] in
            guard let self = self else { return }
            self.frontCard.isHidden = true
            self.frontCard.layer?.removeAllAnimations()
            self.backCard.layer?.removeAllAnimations()
            self.frontCard.layer?.transform = CATransform3DIdentity
            self.backCard.layer?.transform = CATransform3DIdentity
            self.backCard.setDimmerOpacity(0.0)
            self.frontCard.setDimmerOpacity(0.0)
            self.makeFirstResponder(self.backCard.editor)
            self.isAnimating = false
        }

        // Animate front card turning away
        let frontAnim = CAKeyframeAnimation(keyPath: "transform")
        frontAnim.values = frontTransforms.map { NSValue(caTransform3D: $0) }
        frontAnim.duration = duration
        frontAnim.timingFunction = timing
        frontAnim.isRemovedOnCompletion = false
        frontAnim.fillMode = .forwards
        frontCard.layer?.add(frontAnim, forKey: "flip.transform")

        let frontOpacity = CAKeyframeAnimation(keyPath: "opacity")
        frontOpacity.keyTimes = [0.0, 0.48, 0.52, 1.0]
        frontOpacity.values = [1.0, 1.0, 0.0, 0.0]
        frontOpacity.duration = duration
        frontOpacity.isRemovedOnCompletion = false
        frontOpacity.fillMode = .forwards
        frontCard.layer?.add(frontOpacity, forKey: "flip.opacity")

        let frontDim = CABasicAnimation(keyPath: "opacity")
        frontDim.fromValue = 0.0
        frontDim.toValue = 0.35
        frontDim.duration = duration * 0.5
        frontDim.timingFunction = CAMediaTimingFunction(name: .easeIn)
        frontCard.dimmerLayer.add(frontDim, forKey: "flip.dim")

        // Animate back card turning in
        let backAnim = CAKeyframeAnimation(keyPath: "transform")
        backAnim.values = backTransforms.map { NSValue(caTransform3D: $0) }
        backAnim.duration = duration
        backAnim.timingFunction = timing
        backAnim.isRemovedOnCompletion = false
        backAnim.fillMode = .forwards
        backCard.layer?.add(backAnim, forKey: "flip.transform")

        let backOpacity = CAKeyframeAnimation(keyPath: "opacity")
        backOpacity.keyTimes = [0.0, 0.48, 0.52, 1.0]
        backOpacity.values = [0.0, 0.0, 1.0, 1.0]
        backOpacity.duration = duration
        backOpacity.isRemovedOnCompletion = false
        backOpacity.fillMode = .forwards
        backCard.layer?.add(backOpacity, forKey: "flip.opacity")

        let backDim = CABasicAnimation(keyPath: "opacity")
        backDim.fromValue = 0.35
        backDim.toValue = 0.0
        backDim.beginTime = CACurrentMediaTime() + duration * 0.5
        backDim.duration = duration * 0.5
        backDim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        backCard.dimmerLayer.add(backDim, forKey: "flip.dim")

        CATransaction.commit()
    }

    func toggle() {
        if isAnimating { return }
        visibleAsBackside ? hide(animated: true) : reveal()
    }

    func hide(animated: Bool) {
        guard visibleAsBackside else { return }
        if isAnimating { return }

        visibleAsBackside = false
        noteStore.save(backCard.editor.string, for: target)

        let finish: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in
                self?.restoreTargetWindow()
                self?.orderOut(nil)
                self?.isAnimating = false
            }
        }

        guard animated else {
            finish()
            return
        }

        isAnimating = true
        containerView.layoutSubtreeIfNeeded()
        prepareLayersForAnimation()

        frontCard.isHidden = false
        backCard.isHidden = false

        let duration: CFTimeInterval = 0.35
        let timing = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1.0)
        let depth = min(180, max(90, flipHostView.bounds.width * 0.18))

        // Reverse flip: back goes 0 -> -pi, front goes +pi -> 0
        let backTransforms = Self.makeFlipKeyframes(fromAngle: 0, toAngle: -.pi, maxDepth: depth)
        let frontTransforms = Self.makeFlipKeyframes(fromAngle: .pi, toAngle: 0, maxDepth: depth)

        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(timing)
        CATransaction.setCompletionBlock { [weak self] in
            self?.frontCard.layer?.removeAllAnimations()
            self?.backCard.layer?.removeAllAnimations()
            self?.frontCard.layer?.transform = CATransform3DIdentity
            self?.backCard.layer?.transform = CATransform3DIdentity
            finish()
        }

        // Animate back card exiting (0 -> -pi)
        let backAnim = CAKeyframeAnimation(keyPath: "transform")
        backAnim.values = backTransforms.map { NSValue(caTransform3D: $0) }
        backAnim.duration = duration
        backAnim.timingFunction = timing
        backAnim.isRemovedOnCompletion = false
        backAnim.fillMode = .forwards
        backCard.layer?.add(backAnim, forKey: "flip.transform")

        let backOpacity = CAKeyframeAnimation(keyPath: "opacity")
        backOpacity.keyTimes = [0.0, 0.48, 0.52, 1.0]
        backOpacity.values = [1.0, 1.0, 0.0, 0.0]
        backOpacity.duration = duration
        backOpacity.isRemovedOnCompletion = false
        backOpacity.fillMode = .forwards
        backCard.layer?.add(backOpacity, forKey: "flip.opacity")

        let backDim = CABasicAnimation(keyPath: "opacity")
        backDim.fromValue = 0.0
        backDim.toValue = 0.35
        backDim.duration = duration * 0.5
        backDim.timingFunction = CAMediaTimingFunction(name: .easeIn)
        backCard.dimmerLayer.add(backDim, forKey: "flip.dim")

        // Animate front card entering (+pi -> 0)
        let frontAnim = CAKeyframeAnimation(keyPath: "transform")
        frontAnim.values = frontTransforms.map { NSValue(caTransform3D: $0) }
        frontAnim.duration = duration
        frontAnim.timingFunction = timing
        frontAnim.isRemovedOnCompletion = false
        frontAnim.fillMode = .forwards
        frontCard.layer?.add(frontAnim, forKey: "flip.transform")

        let frontOpacity = CAKeyframeAnimation(keyPath: "opacity")
        frontOpacity.keyTimes = [0.0, 0.48, 0.52, 1.0]
        frontOpacity.values = [0.0, 0.0, 1.0, 1.0]
        frontOpacity.duration = duration
        frontOpacity.isRemovedOnCompletion = false
        frontOpacity.fillMode = .forwards
        frontCard.layer?.add(frontOpacity, forKey: "flip.opacity")

        let frontDim = CABasicAnimation(keyPath: "opacity")
        frontDim.fromValue = 0.35
        frontDim.toValue = 0.0
        frontDim.beginTime = CACurrentMediaTime() + duration * 0.5
        frontDim.duration = duration * 0.5
        frontDim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        frontCard.dimmerLayer.add(frontDim, forKey: "flip.dim")

        CATransaction.commit()
    }

    func trackTarget() {
        guard !isAnimating else { return }
        guard hideMethod == .none else { return }
        guard let axFrame = target.frame() else { invalidate(); return }
        let targetRect = Self.appKitFrame(for: axFrame)
        let panelFrame = targetRect.insetBy(dx: -cardMargin, dy: -cardMargin)
        if !panelFrame.equalTo(self.frame) {
            setFrame(panelFrame, display: visibleAsBackside, animate: false)
        }
    }

    func textDidChange(_ notification: Notification) {
        let text = backCard.editor.string
        noteStore.save(text, for: target)
        backCard.updatePlaceholder(isEmpty: text.isEmpty)
    }

    override func cancelOperation(_ sender: Any?) {
        hide(animated: true)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53 { // Escape
            hide(animated: true)
            return
        }
        super.sendEvent(event)
    }

    override func mouseDown(with event: NSEvent) {
        let point = contentView?.convert(event.locationInWindow, from: nil) ?? .zero
        let inHeader = point.y >= (contentView?.bounds.height ?? 0) - cardMargin - 48 &&
                       point.y <= (contentView?.bounds.height ?? 0) - cardMargin
        if event.modifierFlags.contains(.option), inHeader {
            hide(animated: true)
        } else {
            super.mouseDown(with: event)
        }
    }

    private func restoreTargetWindow() {
        guard hideMethod != .none else { return }
        let method = hideMethod
        hideMethod = .none
        TargetWindowHidingService.restore(method: method, pid: target.pid)
    }

    private func prepareLayersForAnimation() {
        let bounds = flipHostView.bounds
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        frontCard.layer?.removeAllAnimations()
        backCard.layer?.removeAllAnimations()
        frontCard.dimmerLayer.removeAllAnimations()
        backCard.dimmerLayer.removeAllAnimations()

        frontCard.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        frontCard.layer?.position = center
        backCard.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        backCard.layer?.position = center
    }

    private static func makeFlipKeyframes(fromAngle: CGFloat, toAngle: CGFloat, maxDepth: CGFloat, steps: Int = 36) -> [CATransform3D] {
        var frames: [CATransform3D] = []
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let angle = fromAngle + (toAngle - fromAngle) * t
            let depth = -maxDepth * sin(t * .pi)
            var transform = CATransform3DIdentity
            transform = CATransform3DTranslate(transform, 0, 0, depth)
            transform = CATransform3DRotate(transform, angle, 0, 1, 0)
            frames.append(transform)
        }
        return frames
    }

    private func invalidate() {
        isInvalid = true
        restoreTargetWindow()
        orderOut(nil)
        onDismiss?(target.key)
    }

    private static func appKitFrame(for axFrame: CGRect) -> NSRect {
        let union = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        return NSRect(x: axFrame.minX, y: union.maxY - axFrame.maxY, width: axFrame.width, height: axFrame.height)
    }
}

// MARK: - Container Views

final class FlipHostContainerView: NSView {
    weak var cardView: NSView?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let cardView = cardView else { return super.hitTest(point) }
        let pointInCard = convert(point, to: cardView)
        if cardView.bounds.contains(pointInCard) {
            return super.hitTest(point)
        }
        return nil
    }
}

// MARK: - Front Window Card View

final class FrontWindowCardView: NSView {
    let card = NSVisualEffectView()
    let dimmerLayer = CALayer()
    private let titleLabel = NSTextField(labelWithString: "")
    private let appNameLabel = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    private let trafficLights = TrafficLightsView()
    private let separator = NSBox()
    private let header = NSView()
    private let snapshotImageView = NSImageView()
    private let placeholderView = NSView()
    private let watermarkIcon = NSImageView()
    private let watermarkTitle = NSTextField(labelWithString: "")
    private let permissionHintButton = NSButton()

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        wantsLayer = true
        layer?.isDoubleSided = false
        layer?.cornerRadius = 12
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.32
        layer?.shadowOffset = CGSize(width: 0, height: -8)
        layer?.shadowRadius = 18

        card.material = .windowBackground
        card.blendingMode = .behindWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.masksToBounds = true
        card.layer?.borderWidth = 0.5
        card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        dimmerLayer.backgroundColor = NSColor.black.cgColor
        dimmerLayer.opacity = 0.0
        dimmerLayer.cornerRadius = 12
        dimmerLayer.masksToBounds = true

        header.translatesAutoresizingMaskIntoConstraints = false

        trafficLights.translatesAutoresizingMaskIntoConstraints = false
        iconView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        appNameLabel.translatesAutoresizingMaskIntoConstraints = false
        appNameLabel.font = .systemFont(ofSize: 11, weight: .regular)
        appNameLabel.textColor = .secondaryLabelColor

        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        header.addSubview(trafficLights)
        header.addSubview(iconView)
        header.addSubview(titleLabel)
        header.addSubview(appNameLabel)
        header.addSubview(separator)

        card.addSubview(header)

        snapshotImageView.translatesAutoresizingMaskIntoConstraints = false
        snapshotImageView.imageScaling = .scaleAxesIndependently
        card.addSubview(snapshotImageView)

        placeholderView.translatesAutoresizingMaskIntoConstraints = false
        watermarkIcon.translatesAutoresizingMaskIntoConstraints = false
        watermarkIcon.alphaValue = 0.22

        watermarkTitle.translatesAutoresizingMaskIntoConstraints = false
        watermarkTitle.font = .systemFont(ofSize: 14, weight: .medium)
        watermarkTitle.textColor = .secondaryLabelColor
        watermarkTitle.alphaValue = 0.6
        watermarkTitle.alignment = .center

        permissionHintButton.translatesAutoresizingMaskIntoConstraints = false
        permissionHintButton.title = "Enable Screen Recording for Live Window Flip"
        permissionHintButton.bezelStyle = .rounded
        permissionHintButton.font = .systemFont(ofSize: 11, weight: .medium)
        permissionHintButton.target = self
        permissionHintButton.action = #selector(openPermissionSettings)

        placeholderView.addSubview(watermarkIcon)
        placeholderView.addSubview(watermarkTitle)
        placeholderView.addSubview(permissionHintButton)
        card.addSubview(placeholderView)

        card.layer?.addSublayer(dimmerLayer)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),

            header.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            header.topAnchor.constraint(equalTo: card.topAnchor),
            header.heightAnchor.constraint(equalToConstant: 44),

            trafficLights.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 14),
            trafficLights.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            trafficLights.widthAnchor.constraint(equalToConstant: 54),
            trafficLights.heightAnchor.constraint(equalToConstant: 14),

            iconView.leadingAnchor.constraint(equalTo: trafficLights.trailingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            appNameLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            appNameLabel.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor, constant: -16),
            appNameLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            separator.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            snapshotImageView.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            snapshotImageView.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            snapshotImageView.topAnchor.constraint(equalTo: card.topAnchor),
            snapshotImageView.bottomAnchor.constraint(equalTo: card.bottomAnchor),

            placeholderView.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            placeholderView.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            placeholderView.topAnchor.constraint(equalTo: header.bottomAnchor),
            placeholderView.bottomAnchor.constraint(equalTo: card.bottomAnchor),

            watermarkIcon.centerXAnchor.constraint(equalTo: placeholderView.centerXAnchor),
            watermarkIcon.centerYAnchor.constraint(equalTo: placeholderView.centerYAnchor, constant: -24),
            watermarkIcon.widthAnchor.constraint(equalToConstant: 64),
            watermarkIcon.heightAnchor.constraint(equalToConstant: 64),

            watermarkTitle.centerXAnchor.constraint(equalTo: placeholderView.centerXAnchor),
            watermarkTitle.topAnchor.constraint(equalTo: watermarkIcon.bottomAnchor, constant: 10),
            watermarkTitle.leadingAnchor.constraint(greaterThanOrEqualTo: placeholderView.leadingAnchor, constant: 32),
            watermarkTitle.trailingAnchor.constraint(lessThanOrEqualTo: placeholderView.trailingAnchor, constant: -32),

            permissionHintButton.centerXAnchor.constraint(equalTo: placeholderView.centerXAnchor),
            permissionHintButton.topAnchor.constraint(equalTo: watermarkTitle.bottomAnchor, constant: 14)
        ])
    }

    override func layout() {
        super.layout()
        layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer?.position = CGPoint(x: frame.midX, y: frame.midY)
        dimmerLayer.frame = card.bounds
    }

    func setDimmerOpacity(_ opacity: Float) {
        dimmerLayer.opacity = opacity
    }

    func update(target: TargetWindow, snapshot: NSImage?) {
        let appIcon = target.appIcon ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        iconView.image = appIcon
        watermarkIcon.image = appIcon

        let displayTitle = target.title.isEmpty ? target.appName : target.title
        titleLabel.stringValue = displayTitle
        watermarkTitle.stringValue = displayTitle
        appNameLabel.stringValue = target.appName

        if let snapshot = snapshot {
            snapshotImageView.image = snapshot
            snapshotImageView.isHidden = false
            header.isHidden = true
            placeholderView.isHidden = true
        } else {
            snapshotImageView.isHidden = true
            header.isHidden = false
            placeholderView.isHidden = false
            permissionHintButton.isHidden = CGPreflightScreenCaptureAccess()
        }
    }

    @objc private func openPermissionSettings() {
        CGRequestScreenCaptureAccess()
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Backside Card View

final class BacksideCardView: NSView {
    let card = NSVisualEffectView()
    let dimmerLayer = CALayer()
    let editor = NSTextView()
    var onFlipBack: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let appIconView = NSImageView()
    private let backsideBadge = NSTextField(labelWithString: "BACKSIDE")
    private let returnButton = NSButton()
    private let separator = NSBox()
    private let placeholderLabel = NSTextField(labelWithString: "Type notes for this window…")

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        wantsLayer = true
        layer?.isDoubleSided = false
        layer?.cornerRadius = 12
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.32
        layer?.shadowOffset = CGSize(width: 0, height: -8)
        layer?.shadowRadius = 18

        card.material = .underWindowBackground
        card.blendingMode = .behindWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.masksToBounds = true
        card.layer?.borderWidth = 0.5
        card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        dimmerLayer.backgroundColor = NSColor.black.cgColor
        dimmerLayer.opacity = 0.0
        dimmerLayer.cornerRadius = 12
        dimmerLayer.masksToBounds = true

        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false

        let flipIcon = NSImageView(image: NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)!)
        flipIcon.contentTintColor = .systemBlue
        flipIcon.translatesAutoresizingMaskIntoConstraints = false

        appIconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        backsideBadge.translatesAutoresizingMaskIntoConstraints = false
        backsideBadge.font = .systemFont(ofSize: 9, weight: .bold)
        backsideBadge.textColor = .secondaryLabelColor
        backsideBadge.wantsLayer = true
        backsideBadge.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        backsideBadge.layer?.cornerRadius = 4
        backsideBadge.alignment = .center

        returnButton.translatesAutoresizingMaskIntoConstraints = false
        returnButton.title = "ESC to return"
        returnButton.bezelStyle = .roundRect
        returnButton.font = .systemFont(ofSize: 11, weight: .medium)
        returnButton.target = self
        returnButton.action = #selector(handleFlipBackClicked)

        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        header.addSubview(flipIcon)
        header.addSubview(appIconView)
        header.addSubview(titleLabel)
        header.addSubview(backsideBadge)
        header.addSubview(returnButton)
        header.addSubview(separator)

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        editor.font = .systemFont(ofSize: 15)
        editor.textColor = .labelColor
        editor.backgroundColor = .clear
        editor.drawsBackground = false
        editor.isRichText = false
        editor.allowsUndo = true
        editor.textContainerInset = NSSize(width: 14, height: 12)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        scroll.documentView = editor

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.font = .systemFont(ofSize: 15)
        placeholderLabel.textColor = .tertiaryLabelColor

        card.addSubview(header)
        card.addSubview(scroll)
        card.addSubview(placeholderLabel)
        card.layer?.addSublayer(dimmerLayer)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),

            header.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            header.topAnchor.constraint(equalTo: card.topAnchor),
            header.heightAnchor.constraint(equalToConstant: 44),

            flipIcon.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            flipIcon.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            flipIcon.widthAnchor.constraint(equalToConstant: 16),
            flipIcon.heightAnchor.constraint(equalToConstant: 16),

            appIconView.leadingAnchor.constraint(equalTo: flipIcon.trailingAnchor, constant: 8),
            appIconView.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            appIconView.widthAnchor.constraint(equalToConstant: 16),
            appIconView.heightAnchor.constraint(equalToConstant: 16),

            titleLabel.leadingAnchor.constraint(equalTo: appIconView.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            backsideBadge.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            backsideBadge.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            backsideBadge.widthAnchor.constraint(equalToConstant: 58),
            backsideBadge.heightAnchor.constraint(equalToConstant: 16),

            returnButton.leadingAnchor.constraint(greaterThanOrEqualTo: backsideBadge.trailingAnchor, constant: 12),
            returnButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -14),
            returnButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            separator.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            scroll.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 6),
            scroll.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -6),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            scroll.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),

            placeholderLabel.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 20),
            placeholderLabel.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 14)
        ])
    }

    override func layout() {
        super.layout()
        layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer?.position = CGPoint(x: frame.midX, y: frame.midY)
        dimmerLayer.frame = card.bounds
    }

    func setDimmerOpacity(_ opacity: Float) {
        dimmerLayer.opacity = opacity
    }

    func updatePlaceholder(isEmpty: Bool) {
        placeholderLabel.isHidden = !isEmpty
    }

    func update(target: TargetWindow) {
        appIconView.image = target.appIcon ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        titleLabel.stringValue = target.title.isEmpty ? target.appName : target.title
    }

    @objc private func handleFlipBackClicked() {
        onFlipBack?()
    }
}

// MARK: - Traffic Lights Drawing

final class TrafficLightsView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let colors: [(fill: NSColor, stroke: NSColor)] = [
            (NSColor(red: 1.0, green: 0.373, blue: 0.337, alpha: 1.0), NSColor(red: 0.88, green: 0.27, blue: 0.24, alpha: 1.0)),
            (NSColor(red: 1.0, green: 0.741, blue: 0.180, alpha: 1.0), NSColor(red: 0.87, green: 0.63, blue: 0.14, alpha: 1.0)),
            (NSColor(red: 0.157, green: 0.784, blue: 0.251, alpha: 1.0), NSColor(red: 0.10, green: 0.67, blue: 0.16, alpha: 1.0))
        ]
        let diameter: CGFloat = 12
        let spacing: CGFloat = 8
        var x: CGFloat = 1
        let y: CGFloat = (bounds.height - diameter) / 2

        for (fill, stroke) in colors {
            let rect = NSRect(x: x, y: y, width: diameter, height: diameter)
            let path = NSBezierPath(ovalIn: rect)
            fill.setFill()
            path.fill()
            stroke.setStroke()
            path.lineWidth = 0.5
            path.stroke()
            x += diameter + spacing
        }
    }
}
