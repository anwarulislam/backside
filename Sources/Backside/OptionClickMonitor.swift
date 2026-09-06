import AppKit
import ApplicationServices

/// A global event tap is used instead of an AppKit monitor so the gesture works while Backside
/// is an accessory app and another application owns the key window.
final class OptionClickMonitor: @unchecked Sendable {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let onOptionClick: @Sendable (CGPoint) -> Void

    init(onOptionClick: @escaping @Sendable (CGPoint) -> Void) {
        self.onOptionClick = onOptionClick
    }

    func start() {
        guard eventTap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: OptionClickMonitor.callback,
            userInfo: context
        )
        guard let eventTap else { return }
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource { CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    func stop() {
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        runLoopSource = nil
        eventTap = nil
    }

    private func received(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .leftMouseDown, event.flags.contains(.maskAlternate) else {
            return Unmanaged.passUnretained(event)
        }
        let point = event.location
        DispatchQueue.main.async { [onOptionClick] in onOptionClick(point) }
        return Unmanaged.passUnretained(event)
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<OptionClickMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        return monitor.received(type: type, event: event)
    }
}
