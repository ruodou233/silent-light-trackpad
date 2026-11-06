import AppKit

// The real actuator state, as the menu bar shows it and as the running instance reports it for `--status`.
enum HapticsStatus: String {
    case off       // Reads off: the normal state.
    case on        // Reads on because the user asked for haptics back.
    case failed    // The user wants haptics off, but the actuator still reads on.
    case unknown   // MultitouchSupport could not be read.

    init(wantsOff: Bool, isEnabled: Bool?) {
        switch isEnabled {
        case false?: self = .off
        case true?: self = wantsOff ? .failed : .on
        case nil: self = .unknown
        }
    }

    // Off and on are both what the user asked for; only these two earn a line of text in the menu.
    var isProblem: Bool { self == .failed || self == .unknown }

    static let reportedStatusKey = "reportedStatus"
    static let reportedPIDKey = "reportedPID"
    static let reportedAtKey = "reportedAt"

    @MainActor
    var menuBarImage: NSImage? {
        guard let hand = NSImage(systemSymbolName: "hand.tap", accessibilityDescription: nil),
              let badge = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 7, weight: .bold)) else { return nil }
        switch self {
        case .off:
            return hand
        case .on:
            // The user asked for haptics back, so this is the tool standing down, not an alarm.
            // SF Symbols has no hand.tap.slash (checked on the macOS 26.5 SDK), so it is the same hand, dimmed.
            let image = NSImage(size: hand.size, flipped: false) { _ in
                hand.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 0.4)
                return true
            }
            image.isTemplate = true
            return image
        case .failed, .unknown:
            // Same hand with a cut-out badge in the lower right: haptics should be off but are not, or cannot be read.
            let image = NSImage(size: NSSize(width: hand.size.width + 4, height: hand.size.height + 1), flipped: false) { rect in
                hand.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
                let badgeRect = NSRect(x: rect.maxX - badge.size.width, y: 0, width: badge.size.width, height: badge.size.height)
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                NSBezierPath(ovalIn: badgeRect.insetBy(dx: -1.2, dy: -1.2)).fill()
                badge.draw(in: badgeRect, from: .zero, operation: .sourceOver, fraction: 1)
                return true
            }
            image.isTemplate = true
            return image
        }
    }
}
