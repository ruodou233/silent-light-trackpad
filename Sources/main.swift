import AppKit

UserDefaults.standard.register(defaults: [
    "pressureThreshold": 50,
    "lightClickEnabled": true,
])

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
