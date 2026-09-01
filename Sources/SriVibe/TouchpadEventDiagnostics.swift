import ApplicationServices
import Foundation

/// Observes the high-level events that macOS may synthesize after consuming a
/// Siri Remote touch surface report. It is listen-only and never alters event
/// delivery. Device identity is not retained by CGEvent, so this is intended
/// for a controlled diagnostic run with no other pointing device in use.
final class TouchpadEventDiagnostics {
    var onDiagnostic: ((String) -> Void)?

    private var eventTap: CFMachPort?
    private var source: CFRunLoopSource?
    private var eventCount = 0
    private let eventLimit = 200

    func start() {
        guard eventTap == nil else { return }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .mouseMoved, .leftMouseDragged, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: Self.callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            onDiagnostic?("Could not create high-level touchpad event diagnostic tap")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        self.source = source
        onDiagnostic?("Listening for high-level mouse and scroll events")
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        eventTap = nil
        eventCount = 0
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<TouchpadEventDiagnostics>.fromOpaque(userInfo).takeUnretainedValue()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = monitor.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
        } else {
            monitor.receive(type: type, event: event)
        }
        return Unmanaged.passUnretained(event)
    }

    private func receive(type: CGEventType, event: CGEvent) {
        guard eventCount < eventLimit else { return }
        eventCount += 1
        let location = event.location
        if type == .scrollWheel {
            let vertical = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
            let horizontal = event.getDoubleValueField(.scrollWheelEventDeltaAxis2)
            onDiagnostic?("High-level scroll dx=\(horizontal) dy=\(vertical) at x=\(location.x) y=\(location.y)")
        } else {
            onDiagnostic?("High-level CGEvent type=\(type.rawValue) at x=\(location.x) y=\(location.y)")
        }
    }
}
