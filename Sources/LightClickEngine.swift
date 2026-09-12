@preconcurrency import AppKit
@preconcurrency import ApplicationServices
import OpenMultitouchSupport

@MainActor
final class LightClickEngine {
    static let shared = LightClickEngine()

    static let injectedMarker: Int64 = 0x534C_5450 // "SLTP"

    var threshold: Float {
        didSet { UserDefaults.standard.set(threshold, forKey: "pressureThreshold") }
    }

    var onPressureChange: ((Float) -> Void)?
    var onStateChange: ((Bool) -> Void)?
    var isRunning: Bool {
        listeningTask != nil && eventTap != nil
    }

    private let manager = OMSManager.shared
    private var listeningTask: Task<Void, Never>?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?

    private var sequence = ClickSequence()
    private var buttonDown: Bool { sequence.buttonDown }
    private var ignoreNativeMouseUpUntil: CFTimeInterval = 0

    private init() {
        threshold = pressureThreshold(from: UserDefaults.standard.object(forKey: "pressureThreshold"))
    }

    func start() -> Bool {
        guard !isRunning else { return true }
        guard installEventTap() else { return false }

        listeningTask = Task { [weak self, manager] in
            for await touches in manager.touchDataStream {
                guard let self else { return }
                self.process(touches)
            }
            guard !Task.isCancelled else { return }
            self?.stop()
        }

        guard manager.startListening() else {
            stop()
            return false
        }
        onStateChange?(true)
        return true
    }

    func stop() {
        releaseButtonIfNeeded()
        listeningTask?.cancel()
        listeningTask = nil
        _ = manager.stopListening()
        if let eventTapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes) }
        if let eventTap { CFMachPortInvalidate(eventTap) }
        eventTapSource = nil
        eventTap = nil
        sequence = ClickSequence()
        onPressureChange?(0)
        onStateChange?(false)
    }

    private func installEventTap() -> Bool {
        let mask = CGEventMask(
            (1 << CGEventType.leftMouseDown.rawValue)
                | (1 << CGEventType.leftMouseUp.rawValue)
                | (1 << CGEventType.mouseMoved.rawValue)
                | (1 << CGEventType.leftMouseDragged.rawValue)
        )
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: pointer
        ) else { return false }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    fileprivate func filter(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == Self.injectedMarker {
            return Unmanaged.passUnretained(event)
        }

        if buttonDown, type == .mouseMoved {
            event.type = .leftMouseDragged
            return Unmanaged.passUnretained(event)
        }

        if buttonDown, type == .leftMouseDown {
            return nil
        }

        if type == .leftMouseUp,
           buttonDown || CACurrentMediaTime() < ignoreNativeMouseUpUntil {
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func process(_ touches: [OMSTouchData]) {
        let active = touches.filter {
            switch $0.state {
            case .starting, .making, .touching, .breaking: true
            default: false
            }
        }

        let result = sequence.update(active.map { ClickTouch(id: $0.id, pressure: $0.pressure) }, threshold: threshold)
        if let pressure = result.pressure { onPressureChange?(pressure) }
        for event in result.events { emit(event) }
    }

    private func releaseButtonIfNeeded() {
        if let event = sequence.release() { emit(event) }
    }

    private func emit(_ event: ClickSequence.Event) {
        postMouseEvent(type: event == .down ? .leftMouseDown : .leftMouseUp)
        if event == .up { ignoreNativeMouseUpUntil = CACurrentMediaTime() + 0.15 }
    }

    private func postMouseEvent(type: CGEventType) {
        let location = CGEvent(source: nil)?.location ?? NSEvent.mouseLocation
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: location,
            mouseButton: .left
        ) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: Self.injectedMarker)
        event.post(tap: .cghidEventTap)
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let engine = Unmanaged<LightClickEngine>.fromOpaque(userInfo).takeUnretainedValue()
    return MainActor.assumeIsolated { engine.filter(type: type, event: event) }
}
