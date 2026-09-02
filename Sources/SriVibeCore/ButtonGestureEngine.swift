import Foundation

public enum GestureOutput: Equatable, Sendable {
    case perform(RemoteButton, ButtonGesture)
}

public struct ButtonGestureEngine: Sendable {
    private var pressedAt: [RemoteButton: Date] = [:]
    private var firedHold: Set<RemoteButton> = []
    private var pendingTaps: [RemoteButton: Date] = [:]
    public var holdThreshold: TimeInterval
    public var doubleTapInterval: TimeInterval

    public init(holdThresholdMilliseconds: Int = 600, doubleTapIntervalMilliseconds: Int = 300) {
        holdThreshold = TimeInterval(min(1_500, max(300, holdThresholdMilliseconds))) / 1_000
        doubleTapInterval = TimeInterval(min(800, max(150, doubleTapIntervalMilliseconds))) / 1_000
    }

    public mutating func press(_ button: RemoteButton, at date: Date) {
        guard pressedAt[button] == nil else { return }
        pressedAt[button] = date
    }

    public mutating func advance(to date: Date) -> [GestureOutput] {
        let eligible = pressedAt.compactMap { button, start -> RemoteButton? in
            !firedHold.contains(button) && date.timeIntervalSince(start) >= holdThreshold ? button : nil
        }
        firedHold.formUnion(eligible)
        let expiredTaps = pendingTaps.compactMap { button, releasedAt -> RemoteButton? in
            date.timeIntervalSince(releasedAt) >= doubleTapInterval ? button : nil
        }
        for button in expiredTaps { pendingTaps.removeValue(forKey: button) }
        return eligible.map { .perform($0, .hold) } + expiredTaps.map { .perform($0, .tap) }
    }

    public mutating func release(_ button: RemoteButton, at date: Date) -> [GestureOutput] {
        guard pressedAt.removeValue(forKey: button) != nil else { return [] }
        if firedHold.remove(button) != nil { return [] }
        if let firstRelease = pendingTaps[button], date.timeIntervalSince(firstRelease) <= doubleTapInterval {
            pendingTaps.removeValue(forKey: button)
            return [.perform(button, .doubleTap)]
        }
        pendingTaps[button] = date
        return []
    }

    public mutating func cancelAll() {
        pressedAt.removeAll()
        firedHold.removeAll()
        pendingTaps.removeAll()
    }
}
