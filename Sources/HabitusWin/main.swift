import AppKit

if CommandLine.arguments.contains("--test-login") {
    let enable = CommandLine.arguments.contains("--on")
    print("before:", LaunchAtLogin.isEnabled)
    if let error = LaunchAtLogin.set(enable) {
        print("error:", error)
    } else {
        print("after:", LaunchAtLogin.isEnabled)
    }
    exit(0)
}

if CommandLine.arguments.contains("--selftest") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    SelfTest.run()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
