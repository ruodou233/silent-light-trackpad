import Foundation

func runSelfTests() -> Int32 {
    var failures: [String] = []
    func check(_ condition: Bool, _ name: String) {
        if !condition { failures.append(name) }
    }
    func touch(_ id: Int32, _ pressure: Float = 80) -> [ClickTouch] {
        [ClickTouch(id: id, pressure: pressure)]
    }
    var sequence = ClickSequence()
    check(sequence.update(touch(1, 49), threshold: 50).events.isEmpty, "below threshold")
    check(sequence.update(touch(1, 50), threshold: 50).events == [.down], "threshold down")
    check(sequence.update(touch(1, 10), threshold: 50).events.isEmpty && sequence.buttonDown, "drag persists below threshold")
    check(sequence.update(touch(2), threshold: 50).events == [.up] && !sequence.buttonDown, "replacement releases without down")
    check(sequence.update(touch(2), threshold: 50).events.isEmpty, "replacement waits for lift")
    check(sequence.update([], threshold: 50).events.isEmpty, "lift clears replacement")
    check(sequence.update(touch(3), threshold: 50).events == [.down], "next contact clicks")
    check(sequence.update([ClickTouch(id: 3, pressure: 80), ClickTouch(id: 4, pressure: 80)], threshold: 50).events == [.up], "multitouch releases")
    check(sequence.update(touch(3), threshold: 50).events.isEmpty, "multitouch waits for lift")
    _ = sequence.update([], threshold: 50)
    _ = sequence.update(touch(5), threshold: 50)
    check(sequence.release() == .up && sequence.release() == nil, "stop releases once")
    check(pressureThreshold(from: nil) == 50, "missing threshold defaults to 50")
    check(pressureThreshold(from: NSNumber(value: 40)) == 40, "saved threshold preserved")
    check(TapSetting.decode(nil) == .missing, "missing preference preserved")
    check(TapSetting.decode(true) == .enabled && TapSetting.decode(false) == .disabled, "boolean preferences")
    check(TapSetting.decode("invalid") == nil, "invalid preference is failure")
    check(TapSetting.cached(current: nil, legacy: true) == .enabled, "legacy true migration")
    check(TapSetting.cached(current: nil, legacy: false) == .disabled, "legacy false migration")
    check(TapSetting.cached(current: "missing", legacy: true) == .missing, "new cache takes precedence")
    check(TapSetting.cached(current: "invalid", legacy: true) == nil, "invalid cache does not silently restore")
    for failure in failures { print("FAIL: \(failure)") }
    print(failures.isEmpty ? "PASS: 19 self-tests (pure state only; no input or preference access)" : "FAILED: \(failures.count)")
    return failures.isEmpty ? 0 : 1
}
