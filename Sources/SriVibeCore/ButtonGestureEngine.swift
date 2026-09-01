import Foundation

public enum GestureOutput: Equatable, Sendable {
    case perform(RemoteButton, ButtonGesture)
}

public struct ButtonGestureEngine: Sendable {
    private var pressedAt: [RemoteButton: Date] = [:]
    private var firedHold: Set<RemoteButton> = []
    public var holdThreshold: TimeInterval

    public init(holdThresholdMilliseconds: Int = 600) {
        holdThreshold = TimeInterval(min(1_500, max(300, holdThresholdMilliseconds))) / 1_000
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
        return eligible.map { .perform($0, .hold) }
    }

    public mutating func release(_ button: RemoteButton, at date: Date) -> [GestureOutput] {
        guard pressedAt.removeValue(forKey: button) != nil else { return [] }
        if firedHold.remove(button) != nil { return [] }
        return [.perform(button, .tap)]
    }

    public mutating func cancelAll() {
        pressedAt.removeAll()
        firedHold.removeAll()
    }
}
