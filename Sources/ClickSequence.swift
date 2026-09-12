import Foundation

func pressureThreshold(from value: Any?) -> Float {
    (value as? NSNumber)?.floatValue ?? 50
}

struct ClickTouch {
    let id: Int32
    let pressure: Float
}

struct ClickSequence {
    enum Event: Equatable { case down, up }
    struct Update {
        var events: [Event] = []
        var pressure: Float?
    }
    private var fingerID: Int32?
    private(set) var buttonDown = false
    private var waitForLift = false

    mutating func release() -> Event? {
        guard buttonDown else { return nil }
        buttonDown = false
        return .up
    }

    mutating func update(_ touches: [ClickTouch], threshold: Float) -> Update {
        if touches.isEmpty {
            let events = release().map { [$0] } ?? []
            self = ClickSequence()
            return Update(events: events, pressure: 0)
        }
        guard !waitForLift else { return Update() }
        guard touches.count == 1, let touch = touches.first,
              fingerID == nil || fingerID == touch.id else {
            // A replacement ID is a new contact, never a continuation of a drag.
            let events = release().map { [$0] } ?? []
            fingerID = nil
            waitForLift = true
            return Update(events: events, pressure: 0)
        }
        fingerID = touch.id
        let pressure = max(0, touch.pressure)
        if !buttonDown, pressure >= threshold {
            buttonDown = true
            return Update(events: [.down], pressure: pressure)
        }
        return Update(pressure: pressure)
    }
}
