import AppKit
import ApplicationServices

enum TargetWindowHidingService {
    enum HideMethod: Equatable, Sendable {
        case none
        case scriptableWindow(bundleID: String, windowNumber: CGWindowID, title: String)
        case applicationHidden(pid: pid_t)
    }

    /// Intelligently hides the target window for the 3D flip effect.
    /// Prefers window-level hiding via AppleScript so the target application remains frontmost
    /// without deactivating or switching focus to the underlying application.
    /// Falls back to application-level hide if window-level hiding is unsupported.
    @discardableResult
    @MainActor
    static func hideWindow(for target: TargetWindow) -> HideMethod {
        guard let app = NSRunningApplication(processIdentifier: target.pid),
              let bundleID = app.bundleIdentifier else {
            return .none
        }

        // 1. Try scriptable window-level visibility toggle
        if hideScriptableWindow(bundleID: bundleID, windowNumber: target.windowNumber, title: target.title) {
            return .scriptableWindow(bundleID: bundleID, windowNumber: target.windowNumber, title: target.title)
        }

        // 2. Fallback: hide target app if window-level hiding is unsupported
        let axApp = AXUIElementCreateApplication(target.pid)
        let err = AXUIElementSetAttributeValue(axApp, "AXHidden" as CFString, kCFBooleanTrue)
        if err == .success {
            return .applicationHidden(pid: target.pid)
        }

        return .none
    }

    nonisolated static func restore(method: HideMethod, pid: pid_t) {
        switch method {
        case .none:
            break
        case let .scriptableWindow(bundleID, windowNumber, title):
            restoreScriptableWindow(bundleID: bundleID, windowNumber: windowNumber, title: title)
            NSRunningApplication(processIdentifier: pid)?.activate()
        case .applicationHidden:
            let axApp = AXUIElementCreateApplication(pid)
            AXUIElementSetAttributeValue(axApp, "AXHidden" as CFString, kCFBooleanFalse)
            NSRunningApplication(processIdentifier: pid)?.activate()
        }
    }

    private static func hideScriptableWindow(bundleID: String, windowNumber: CGWindowID, title: String) -> Bool {
        let escapedTitle = title
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let scriptSource = """
        tell application id "\(bundleID)"
            try
                set visible of (first window whose id is \(windowNumber)) to false
                return true
            on error
                try
                    set visible of (first window whose name contains "\(escapedTitle)") to false
                    return true
                on error
                    try
                        set visible of window 1 to false
                        return true
                    on error
                        return false
                    end try
                end try
            end try
        end tell
        """
        var error: NSDictionary?
        let script = NSAppleScript(source: scriptSource)
        let result = script?.executeAndReturnError(&error)
        return result?.booleanValue ?? false
    }

    private nonisolated static func restoreScriptableWindow(bundleID: String, windowNumber: CGWindowID, title: String) {
        let escapedTitle = title
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let scriptSource = """
        tell application id "\(bundleID)"
            try
                set visible of (first window whose id is \(windowNumber)) to true
            on error
                try
                    set visible of (first window whose name contains "\(escapedTitle)") to true
                on error
                    try
                        set visible of window 1 to true
                    end try
                end try
            end try
        end tell
        """
        var error: NSDictionary?
        let script = NSAppleScript(source: scriptSource)
        _ = script?.executeAndReturnError(&error)
    }
}
