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

    static let reportedStatusKey = "reportedStatus"
    static let reportedPIDKey = "reportedPID"
    static let reportedAtKey = "reportedAt"

    @MainActor
    var menuBarImage: NSImage? {
        let description = "Silent Light Trackpad"
        guard let hand = NSImage(systemSymbolName: "hand.tap", accessibilityDescription: description) else { return nil }
        guard self != .off,
              let badge = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 8, weight: .bold)) else { return hand }
        // Same hand with a cut-out badge in the lower right: haptics are not off right now.
        let image = NSImage(size: NSSize(width: hand.size.width + 4, height: hand.size.height + 1), flipped: false) { rect in
            hand.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
            let badgeRect = NSRect(x: rect.maxX - badge.size.width, y: 0, width: badge.size.width, height: badge.size.height)
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: badgeRect.insetBy(dx: -1.5, dy: -1.5)).fill()
            badge.draw(in: badgeRect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = description
        return image
    }
}
