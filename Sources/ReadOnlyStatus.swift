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
    let status: [String: Any] = [
        "bundleVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? NSNull(),
        "SMAppService.mainApp.status": loginStatus,
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
