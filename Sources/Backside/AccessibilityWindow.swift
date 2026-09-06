import AppKit
import ApplicationServices

struct TargetWindow: Hashable {
    let element: AXUIElement
    let pid: pid_t
    let key: String
    let title: String

    static func at(screenPoint: CGPoint) -> TargetWindow? {
        var hit: AXUIElement?
        let system = AXUIElementCreateSystemWide()
        guard AXUIElementCopyElementAtPosition(system, Float(screenPoint.x), Float(screenPoint.y), &hit) == .success,
              let initial = hit,
              let window = enclosingWindow(of: initial),
              let pid = pid(of: window),
              pid != ProcessInfo.processInfo.processIdentifier,
              isTitleBarHit(initial, window: window, point: screenPoint) else { return nil }

        let title = string(window, kAXTitleAttribute) ?? "Untitled window"
        let number = numberAttribute(window, "AXWindowNumber") ?? 0
        let app = NSRunningApplication(processIdentifier: pid)
        // Window number distinguishes otherwise identically titled document windows for a session.
        let key = "\(app?.bundleIdentifier ?? "pid.\(pid)")|\(number)|\(title)"
        return TargetWindow(element: window, pid: pid, key: key, title: title)
    }

    func frame() -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    private static func enclosingWindow(of start: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = start
        for _ in 0..<12 {
            guard let element = current else { return nil }
            if string(element, kAXRoleAttribute) == kAXWindowRole { return element }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent) == .success else { return nil }
            current = parent as! AXUIElement?
        }
        return nil
    }

    private static func pid(of element: AXUIElement) -> pid_t? {
        var value: pid_t = 0
        return AXUIElementGetPid(element, &value) == .success ? value : nil
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func numberAttribute(_ element: AXUIElement, _ attribute: String) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? Int
    }

    private static func isTitleBarHit(_ initial: AXUIElement, window: AXUIElement, point: CGPoint) -> Bool {
        // Many apps expose the chrome as AXToolbar, AXTitle, or a traffic-light button rather
        // than returning AXWindow for a click in that area. Treat these semantic hit targets as
        // title-bar clicks first; this avoids relying solely on a coordinate heuristic.
        var current: AXUIElement? = initial
        let headerRoles: Set<String> = ["AXTitle", "AXToolbar", "AXCloseButton", "AXMinimizeButton", "AXZoomButton"]
        for _ in 0..<8 {
            guard let element = current else { break }
            if let role = string(element, kAXRoleAttribute), headerRoles.contains(role) { return true }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent) == .success else { break }
            current = parent as! AXUIElement?
        }
        guard let frame = TargetWindow(element: window, pid: 0, key: "", title: "").frame() else { return false }
        // Unified title/toolbar apps commonly reserve 80–100 points. A 120 point header band
        // makes blank title bars and traffic-light areas reliable without making normal content
        // clicks accidental toggles.
        let titleBand = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: min(120, frame.height))
        return titleBand.contains(point)
    }
}
