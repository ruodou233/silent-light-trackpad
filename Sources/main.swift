import AppKit

if CommandLine.arguments.contains("--self-test") {
    exit(runSelfTests())
}

UserDefaults.standard.register(defaults: [
    "pressureThreshold": 50,
    "lightClickEnabled": true,
])

if CommandLine.arguments.contains("--status") {
    exit(printReadOnlyStatus())
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
