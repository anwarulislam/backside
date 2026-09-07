import AppKit
import ApplicationServices

struct TargetWindow: Hashable {
    let element: AXUIElement
    let pid: pid_t
    let key: String
    let title: String
    let appBundleID: String
    let appName: String
    let windowNumber: CGWindowID

    init(
        element: AXUIElement,
        pid: pid_t,
        key: String,
        title: String,
        appBundleID: String,
        appName: String,
        windowNumber: CGWindowID = 0
    ) {
        self.element = element
        self.pid = pid
        self.key = key
        self.title = title
        self.appBundleID = appBundleID
        self.appName = appName
        self.windowNumber = windowNumber
    }

    var appIcon: NSImage? {
        if let app = NSRunningApplication(processIdentifier: pid), let icon = app.icon {
            return icon
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appBundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return nil
    }

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
        let wid = windowID(for: window)
        let number = wid != 0 ? Int(wid) : (numberAttribute(window, "AXWindowNumber") ?? 0)
        let app = NSRunningApplication(processIdentifier: pid)
        let appBundleID = app?.bundleIdentifier ?? "pid.\(pid)"
        let appName = app?.localizedName ?? appBundleID
        // Window number distinguishes otherwise identically titled document windows for a session.
        let key = "\(appBundleID)|\(number)|\(title)"
        return TargetWindow(
            element: window,
            pid: pid,
            key: key,
            title: title,
            appBundleID: appBundleID,
            appName: appName,
            windowNumber: CGWindowID(number)
        )
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

    private typealias AXUIElementGetWindowFunc = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    private static let getWindowIDFunc: AXUIElementGetWindowFunc? = {
        guard let sym = dlsym(dlopen(nil, RTLD_NOW), "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(sym, to: AXUIElementGetWindowFunc.self)
    }()

    static func windowID(for element: AXUIElement) -> CGWindowID {
        var wid: CGWindowID = 0
        if let fn = getWindowIDFunc, fn(element, &wid) == .success, wid != 0 {
            return wid
        }
        return 0
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
        guard let frame = TargetWindow(element: window, pid: 0, key: "", title: "", appBundleID: "", appName: "").frame() else { return false }
        // Unified title/toolbar apps commonly reserve 80–100 points. A 120 point header band
        // makes blank title bars and traffic-light areas reliable without making normal content
        // clicks accidental toggles.
        let titleBand = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: min(120, frame.height))
        return titleBand.contains(point)
    }
}
