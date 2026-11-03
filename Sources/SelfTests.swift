import Foundation

func runSelfTests() -> Int32 {
    var failures: [String] = []
    func check(_ condition: Bool, _ name: String) {
        if !condition { failures.append(name) }
    }
    for key in ["lightClickEnabled", "pressureThreshold", "originalTapToClickState", "originalTapToClick"] {
        check(AppDelegate.legacyPreferenceKeys.contains(key), "legacy key cleared: \(key)")
    }
    check(!AppDelegate.legacyPreferenceKeys.contains("launchAtLoginEnabled"), "login choice survives cleanup")
    for failure in failures { print("FAIL: \(failure)") }
    print(failures.isEmpty ? "PASS: 5 self-tests (pure state only; no input or preference access)" : "FAILED: \(failures.count)")
    return failures.isEmpty ? 0 : 1
}
