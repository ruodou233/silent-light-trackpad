import AppKit
import ServiceManagement

@MainActor
func printReadOnlyStatus() -> Int32 {
    let loginStatus: String
    switch SMAppService.mainApp.status {
    case .notRegistered: loginStatus = "notRegistered"
    case .enabled: loginStatus = "enabled"
    case .requiresApproval: loginStatus = "requiresApproval"
    case .notFound: loginStatus = "notFound"
    @unknown default: loginStatus = "unknown"
    }
    // The running instance reports its own state; this process only checks that it is still alive.
    let defaults = UserDefaults.standard
    let reportedPID = defaults.object(forKey: HapticsStatus.reportedPIDKey) as? Int
    let reporter = reportedPID.flatMap { NSRunningApplication(processIdentifier: pid_t($0)) }
    let reportedAt = defaults.object(forKey: HapticsStatus.reportedAtKey) as? Date
    let status: [String: Any] = [
        "bundleVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? NSNull(),
        "SMAppService.mainApp.status": loginStatus,
        "instance.running": reporter != nil && reporter?.bundleIdentifier == Bundle.main.bundleIdentifier,
        "instance.status": defaults.string(forKey: HapticsStatus.reportedStatusKey) ?? NSNull(),
        "instance.reportedAt": reportedAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
        // Direct read of MTActuatorGetSystemActuationsEnabled, for cross-checking the report.
        "haptics.isEnabled": HapticsController.shared.readEnabled().map { $0 as Any } ?? NSNull(),
    ]
    do {
        let data = try JSONSerialization.data(withJSONObject: status, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        return 0
    } catch {
        FileHandle.standardError.write(Data("Could not encode status: \(error)\n".utf8))
        return 1
    }
}
