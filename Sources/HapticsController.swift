import Foundation

private typealias CreateDevice = @convention(c) () -> UnsafeMutableRawPointer?
private typealias GetActuator = @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?
private typealias GetEnabled = @convention(c) (UnsafeMutableRawPointer) -> Int
private typealias SetEnabled = @convention(c) (UnsafeMutableRawPointer, Int) -> Int32
private typealias ReleaseDevice = @convention(c) (UnsafeMutableRawPointer) -> Void

@MainActor
final class HapticsController {
    static let shared = HapticsController()

    private let handle: UnsafeMutableRawPointer?
    private let createDevice: CreateDevice?
    private let getActuator: GetActuator?
    private let getEnabled: GetEnabled?
    private let setEnabled: SetEnabled?
    private let releaseDevice: ReleaseDevice?
    private(set) var isEnabled: Bool?

    private init() {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        handle = dlopen(path, RTLD_NOW)
        createDevice = Self.symbol("MTDeviceCreateDefault", in: handle)
        getActuator = Self.symbol("MTDeviceGetMTActuator", in: handle)
        getEnabled = Self.symbol("MTActuatorGetSystemActuationsEnabled", in: handle)
        setEnabled = Self.symbol("MTActuatorSetSystemActuationsEnabled", in: handle)
        releaseDevice = Self.symbol("MTDeviceRelease", in: handle)
    }

    private static func symbol<T>(_ name: String, in handle: UnsafeMutableRawPointer?) -> T? {
        guard let handle, let raw = dlsym(handle, name) else { return nil }
        return unsafeBitCast(raw, to: T.self)
    }

    @discardableResult
    func readEnabled() -> Bool? {
        guard let createDevice, let getActuator, let getEnabled, let releaseDevice,
              let device = createDevice() else {
            isEnabled = nil
            return nil
        }
        defer { releaseDevice(device) }
        guard let actuator = getActuator(device) else {
            isEnabled = nil
            return nil
        }
        isEnabled = Self.decode(getEnabled(actuator))
        return isEnabled
    }

    func setEnabled(_ enabled: Bool) -> Bool {
        guard let createDevice, let getActuator, let getEnabled, let setEnabled, let releaseDevice,
              let device = createDevice() else {
            isEnabled = nil
            return false
        }
        defer { releaseDevice(device) }
        guard let actuator = getActuator(device), setEnabled(actuator, enabled ? 1 : 0) == 0 else {
            isEnabled = nil
            return false
        }
        isEnabled = Self.decode(getEnabled(actuator))
        return isEnabled == enabled
    }

    // From PR #2: never turn the actuator off blind. It is turned off only after it answers with a
    // definite on or off; turning haptics back on is always tried.
    nonisolated static func shouldWrite(enabled: Bool, current: Bool?) -> Bool {
        enabled || current != nil
    }

    private static func decode(_ value: Int) -> Bool? {
        value == 0 ? false : (value == 1 ? true : nil)
    }
}
