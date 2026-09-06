import AppKit

@MainActor
final class BacksideCoordinator: NSObject {
    private let store: NoteStore
    private var panels: [String: ScratchpadPanel] = [:]
    private var trackingTimer: Timer?

    init(store: NoteStore) {
        self.store = store
        super.init()
        trackingTimer = Timer.scheduledTimer(timeInterval: 1.0 / 30.0, target: self, selector: #selector(trackPanels), userInfo: nil, repeats: true)
        RunLoop.main.add(trackingTimer!, forMode: .common)
    }

    func toggleWindow(at screenPoint: CGPoint) {
        guard AXIsProcessTrusted() else {
            NSSound.beep()
            return
        }
        guard let target = TargetWindow.at(screenPoint: screenPoint) else { return }
        if let existing = panels[target.key] {
            existing.toggle()
        } else {
            let panel = ScratchpadPanel(target: target, noteStore: store)
            panel.onDismiss = { [weak self] key in self?.panels.removeValue(forKey: key) }
            panels[target.key] = panel
            panel.reveal()
        }
    }

    func hideAll() { panels.values.forEach { $0.hide(animated: false) } }

    @objc private func trackPanels() {
        panels = panels.filter { _, panel in
            panel.trackTarget()
            return !panel.isInvalid
        }
    }
}
