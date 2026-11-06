import Foundation

func runSelfTests() -> Int32 {
    var failures: [String] = []
    func check(_ condition: Bool, _ name: String) {
        if !condition { failures.append(name) }
    }
    for key in ["lightClickEnabled", "pressureThreshold", "originalTapToClickState", "originalTapToClick", "restorePending"] {
        check(AppDelegate.legacyPreferenceKeys.contains(key), "legacy key cleared: \(key)")
    }
    for key in ["launchAtLoginEnabled", "hapticsWanted", HapticsStatus.reportedStatusKey] {
        check(!AppDelegate.legacyPreferenceKeys.contains(key), "current key survives cleanup: \(key)")
    }
    check(HapticsStatus(wantsOff: true, isEnabled: false) == .off, "off when actuator reads off")
    check(HapticsStatus(wantsOff: false, isEnabled: false) == .off, "off is reported even if haptics were wanted")
    check(HapticsStatus(wantsOff: false, isEnabled: true) == .on, "on when the user asked for haptics")
    check(HapticsStatus(wantsOff: true, isEnabled: true) == .failed, "failed when off was wanted but reads on")
    check(HapticsStatus(wantsOff: true, isEnabled: nil) == .unknown, "unknown when unreadable")
    check(!HapticsStatus.off.isProblem && !HapticsStatus.on.isProblem, "no menu line when haptics are as the user asked")
    check(HapticsStatus.failed.isProblem && HapticsStatus.unknown.isProblem, "menu line when off failed or state is unreadable")
    for failure in failures { print("FAIL: \(failure)") }
    print(failures.isEmpty ? "PASS: 15 self-tests (pure state only; no input or preference access)" : "FAILED: \(failures.count)")
    return failures.isEmpty ? 0 : 1
}
