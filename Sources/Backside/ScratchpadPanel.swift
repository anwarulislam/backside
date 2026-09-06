import AppKit

@MainActor
final class ScratchpadPanel: NSPanel, NSTextViewDelegate {
    let target: TargetWindow
    var onDismiss: ((String) -> Void)?
    private let noteStore: NoteStore
    private let editor = NSTextView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let card = NSVisualEffectView()
    private var visibleAsBackside = false
    private(set) var isInvalid = false

    init(target: TargetWindow, noteStore: NoteStore) {
        self.target = target
        self.noteStore = noteStore
        noteStore.register(target)
        let initialFrame = Self.appKitFrame(for: target.frame() ?? .zero)
        super.init(
            contentRect: initialFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        titleVisibility = .hidden
        animationBehavior = .utilityWindow
        setupView()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    private func setupView() {
        card.material = .underWindowBackground
        card.blendingMode = .behindWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.masksToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false

        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        let icon = NSImageView(image: NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: nil)!)
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.stringValue = target.title
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        let hint = NSTextField(labelWithString: "ESC to return")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(icon)
        header.addSubview(titleLabel)
        header.addSubview(hint)

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        editor.string = noteStore.note(for: target.key)
        editor.font = .systemFont(ofSize: 15)
        editor.textColor = .labelColor
        editor.backgroundColor = .clear
        editor.drawsBackground = false
        editor.isRichText = false
        editor.allowsUndo = true
        editor.delegate = self
        editor.textContainerInset = NSSize(width: 10, height: 8)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        scroll.documentView = editor

        let content = NSView()
        content.addSubview(card)
        card.addSubview(header)
        card.addSubview(scroll)
        self.contentView = content
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: content.leadingAnchor), card.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            card.topAnchor.constraint(equalTo: content.topAnchor), card.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            header.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18), header.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            header.topAnchor.constraint(equalTo: card.topAnchor, constant: 13), header.heightAnchor.constraint(equalToConstant: 20),
            icon.leadingAnchor.constraint(equalTo: header.leadingAnchor), icon.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7), titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            hint.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8), hint.trailingAnchor.constraint(equalTo: header.trailingAnchor), hint.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            scroll.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8), scroll.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 7), scroll.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10)
        ])
    }

    func reveal() {
        guard let frame = target.frame() else { invalidate(); return }
        setFrame(Self.appKitFrame(for: frame), display: true)
        alphaValue = 0
        setCardTransform(flipTransform(angle: .pi / 2.25))
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        visibleAsBackside = true
        animateFlip(from: flipTransform(angle: .pi / 2.25), to: CATransform3DIdentity, duration: 0.24)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().alphaValue = 1
        }
        makeFirstResponder(editor)
    }

    func toggle() { visibleAsBackside ? hide(animated: true) : reveal() }

    func hide(animated: Bool) {
        guard visibleAsBackside else { return }
        visibleAsBackside = false
        noteStore.save(editor.string, for: target)
        let finish: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in
                self?.orderOut(nil)
                self?.restoreTargetApplication()
            }
        }
        guard animated else { finish(); return }
        animateFlip(from: CATransform3DIdentity, to: flipTransform(angle: -.pi / 2.25), duration: 0.18)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            animator().alphaValue = 0
        }, completionHandler: finish)
    }

    func trackTarget() {
        guard let axFrame = target.frame() else { invalidate(); return }
        let frame = Self.appKitFrame(for: axFrame)
        if !frame.equalTo(self.frame) { setFrame(frame, display: visibleAsBackside, animate: false) }
    }

    func textDidChange(_ notification: Notification) { noteStore.save(editor.string, for: target) }

    override func cancelOperation(_ sender: Any?) { hide(animated: true) }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53 { // Escape
            hide(animated: true)
            return
        }
        super.sendEvent(event)
    }

    override func mouseDown(with event: NSEvent) {
        let point = contentView?.convert(event.locationInWindow, from: nil) ?? .zero
        let inHeader = point.y >= (contentView?.bounds.height ?? 0) - 48
        if event.modifierFlags.contains(.option), inHeader {
            hide(animated: true)
        } else {
            super.mouseDown(with: event)
        }
    }

    private func invalidate() {
        isInvalid = true
        orderOut(nil)
        onDismiss?(target.key)
    }

    /// AX coordinates begin at the main display's upper-left; AppKit coordinates begin lower-left.
    private static func appKitFrame(for axFrame: CGRect) -> NSRect {
        let union = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        return NSRect(x: axFrame.minX, y: union.maxY - axFrame.maxY, width: axFrame.width, height: axFrame.height)
    }

    private func flipTransform(angle: CGFloat) -> CATransform3D {
        var transform = CATransform3DIdentity
        transform.m34 = -1 / 900
        return CATransform3DRotate(transform, angle, 0, 1, 0)
    }

    private func animateFlip(from: CATransform3D, to: CATransform3D, duration: CFTimeInterval) {
        guard let layer = card.layer else { return }
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: from)
        animation.toValue = NSValue(caTransform3D: to)
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "backside.flip")
        setCardTransform(to)
    }

    private func setCardTransform(_ transform: CATransform3D) {
        guard let layer = card.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = transform
        CATransaction.commit()
    }

    private func restoreTargetApplication() {
        NSRunningApplication(processIdentifier: target.pid)?.activate(options: [])
    }
}
