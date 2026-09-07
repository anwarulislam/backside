import AppKit
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let noteStore = NoteStore()
    private lazy var coordinator = BacksideCoordinator(store: noteStore)
    private lazy var clickMonitor = OptionClickMonitor { [weak self] point in
        Task { @MainActor [weak self] in
            self?.coordinator.toggleWindow(at: point)
        }
    }
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenuBar()
        requestAccessibilityIfNeeded()
        requestScreenCaptureIfNeeded()
        clickMonitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        clickMonitor.stop()
    }

    private func configureMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "Backside")
        statusItem.button?.toolTip = "Backside — Option-click a window title bar"

        let menu = NSMenu()
        menu.addItem(withTitle: "Backside", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Grant Accessibility Access…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        menu.addItem(withTitle: "Grant Screen Recording Access…", action: #selector(openScreenRecordingSettings), keyEquivalent: "")
        menu.addItem(withTitle: "Open Note Library", action: #selector(openLibrary), keyEquivalent: "l")
        menu.addItem(withTitle: "Hide All Scratchpads", action: #selector(hideAll), keyEquivalent: "h")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Backside", action: #selector(quit), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        // Spell out the documented key to avoid importing a mutable C global into Swift concurrency.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func requestScreenCaptureIfNeeded() {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }

    @objc private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func hideAll() { coordinator.hideAll() }
    @objc private func openLibrary() { coordinator.showLibrary() }
    @objc private func quit() { NSApp.terminate(nil) }
}
