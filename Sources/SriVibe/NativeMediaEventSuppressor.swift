import AppKit
import ApplicationServices
import Foundation

/// Prevents the Siri Remote's physical Play/Pause consumer event from reaching
/// media applications after SriVibe has claimed that press as a remote command.
///
/// HID seizing supplies the button report to this app, but macOS can still emit
/// a `systemDefined` media-key event for consumer usage 0xCD.  An event tap is
/// the last routing point before applications such as Chrome receive it.
final class NativeMediaEventSuppressor {
    // `NSSystemDefined` is intentionally not surfaced as a named Swift
    // CGEventType case; its documented AppKit event number is 14.
    private static let systemDefinedEvent = CGEventType(rawValue: 14)!
    private let lock = NSLock()
    private var playPauseDeadline: TimeInterval = 0
    private var suppressedVolumeDeadlines: [Int: TimeInterval] = [:]
    private var eventTap: CFMachPort?
    private var source: CFRunLoopSource?

    func start() {
        guard eventTap == nil else { return }
        let mask = CGEventMask(1) << Self.systemDefinedEvent.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.eventTap = tap
        self.source = source
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        eventTap = nil
        lock.lock()
        playPauseDeadline = 0
        suppressedVolumeDeadlines.removeAll()
        lock.unlock()
    }

    /// Call at the physical press, before the system-generated media event is
    /// delivered. A short window avoids affecting keyboard media keys.
    func suppressNextPlayPauseEvent() {
        lock.lock()
        playPauseDeadline = ProcessInfo.processInfo.systemUptime + 0.35
        lock.unlock()
    }

    func beginSuppressingVolume(up: Bool) {
        lock.lock()
        suppressedVolumeDeadlines[up ? 0 : 1] = .infinity // NX_KEYTYPE_SOUND_UP / DOWN
        lock.unlock()
    }

    func endSuppressingVolume(up: Bool) {
        lock.lock()
        // The system-defined media event can arrive after the HID release.
        // Retain the interception briefly so quick repeated taps don't leak
        // through as native volume changes.
        suppressedVolumeDeadlines[up ? 0 : 1] = ProcessInfo.processInfo.systemUptime + 0.45
        lock.unlock()
    }

    private func shouldSuppressPlayPause() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = ProcessInfo.processInfo.systemUptime
        guard now <= playPauseDeadline else { return false }
        return true
    }

    private func shouldSuppressVolume(_ keyCode: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let deadline = suppressedVolumeDeadlines[keyCode] else { return false }
        if deadline < ProcessInfo.processInfo.systemUptime {
            suppressedVolumeDeadlines.removeValue(forKey: keyCode)
            return false
        }
        return true
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let suppressor = Unmanaged<NativeMediaEventSuppressor>.fromOpaque(userInfo).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = suppressor.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == NativeMediaEventSuppressor.systemDefinedEvent else { return Unmanaged.passUnretained(event) }

        // NX_KEYTYPE_PLAY, encoded in the high word of an NSSystemDefined event.
        let mediaKeyCode = Int(((NSEvent(cgEvent: event)?.data1 ?? 0) >> 16) & 0xFFFF)
        if mediaKeyCode == 16, suppressor.shouldSuppressPlayPause() { return nil }
        if (mediaKeyCode == 0 || mediaKeyCode == 1), suppressor.shouldSuppressVolume(mediaKeyCode) { return nil }
        return Unmanaged.passUnretained(event)
    }
}
