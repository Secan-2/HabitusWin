import AppKit

if CommandLine.arguments.contains("--test-force") {
    let bundleID = CommandLine.arguments.dropFirst().first(where: { $0 != "--test-force" })
        ?? "com.zentraedi.zspaceMacApp"
    ForceQuit.terminateTree(bundleID: bundleID)
    RunLoop.main.run(until: Date().addingTimeInterval(1))
    exit(0)
}

if CommandLine.arguments.contains("--test-quit"),
   let idx = CommandLine.arguments.firstIndex(of: "--test-quit"),
   idx + 1 < CommandLine.arguments.count,
   let target = pid_t(CommandLine.arguments[idx + 1]) {
    WindowActions.quit(pid: target, window: nil)
    RunLoop.main.run(until: Date().addingTimeInterval(4))
    print("test-quit finished")
    exit(0)
}

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
