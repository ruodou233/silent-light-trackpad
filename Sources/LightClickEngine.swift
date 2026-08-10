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
    private(set) var isRunning = false

    private let manager = OMSManager.shared
    private var listeningTask: Task<Void, Never>?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?

    private var enabled = false
    private var fingerID: Int32?
    private var buttonDown = false
    private var sequenceActive = false
    private var lastPressure: Float = 0
    private var ignoreNativeMouseUpUntil: CFTimeInterval = 0

    private init() {
        let saved = UserDefaults.standard.float(forKey: "pressureThreshold")
        threshold = saved > 0 ? saved : 50
    }

    func start() -> Bool {
        guard !enabled else { return true }
        guard installEventTap() else { return false }

        listeningTask = Task { [weak self, manager] in
            for await touches in manager.touchDataStream {
                guard let self else { return }
                self.process(touches)
            }
        }

        guard manager.startListening() else {
            stop()
            return false
        }
        enabled = true
        isRunning = true
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
        enabled = false
        isRunning = false
        resetSequence()
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

        guard active.count == 1, let touch = active.first else {
            if active.isEmpty {
                finishSequence()
            } else if sequenceActive {
                releaseButtonIfNeeded()
                resetSequence()
            }
            return
        }

        if fingerID == nil {
            fingerID = touch.id
            sequenceActive = true
        }
        guard fingerID == touch.id else { return }

        lastPressure = max(0, touch.pressure)
        onPressureChange?(lastPressure)

        if !buttonDown, lastPressure >= threshold {
            postMouseEvent(type: .leftMouseDown)
            buttonDown = true
        }
    }

    private func finishSequence() {
        guard sequenceActive else { return }
        releaseButtonIfNeeded()
        resetSequence()
    }

    private func releaseButtonIfNeeded() {
        guard buttonDown else { return }
        postMouseEvent(type: .leftMouseUp)
        buttonDown = false
        ignoreNativeMouseUpUntil = CACurrentMediaTime() + 0.15
    }

    private func resetSequence() {
        fingerID = nil
        sequenceActive = false
        lastPressure = 0
        onPressureChange?(0)
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
