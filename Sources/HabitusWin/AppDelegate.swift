import AppKit
import Combine
import CoreServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private var statusItemController: StatusItemController?
    private var windowClick: WindowClickModule?
    private var cutPaste: CutPasteModule?
    private var dockClick: DockClickModule?
    private var settingsWindowController: SettingsWindowController?
    private var bag = Set<AnyCancellable>()
    private var permissionRequested = false
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 覆盖安装或从不可靠路径拷贝后，主动补一次 LaunchServices 注册，
        // 让启动台与访达立刻拿到正确的图标和元数据。
        _ = LSRegisterURL(Bundle.main.bundleURL as CFURL, true)

        statusItemController = StatusItemController(settings: settings) { [weak self] in
            self?.openSettings()
        }

        // 模块在初始化时注册事件处理，监听本身按需启停。
        windowClick = WindowClickModule(settings: settings)
        cutPaste = CutPasteModule(settings: settings)
        dockClick = DockClickModule(settings: settings)

        settings.changes
            .sink { [weak self] in self?.handleSettingsChange() }
            .store(in: &bag)

        updateTap()
        if anyFeatureEnabled(), !Permissions.isAccessibilityTrusted {
            startPermissionWatch()
        }

        if settings.wasFirstRun || CommandLine.arguments.contains("--settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.openSettings(pageIndex: 3)
            }
        }

        if settings.wasFirstRun {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.showWelcome()
            }
        }
    }

    /// 首次启动的说明。未做公证，这两件事必须提前讲清楚，否则用户会在第一步放弃。
    private func showWelcome() {
        let alert = NSAlert()
        alert.messageText = "欢迎使用 HabitusWin"
        alert.informativeText = """
        三个功能默认全部关闭，系统行为与安装前完全一致。需要哪个，到设置里打开对应开关即可。

        首次打开开关时，系统会请求「辅助功能」权限，勾选后 1 到 2 秒内自动生效。

        如果打开应用时提示「无法验证开发者」，到「系统设置 → 隐私与安全性」点「仍要打开」。这一步只需要做一次。
        """
        alert.addButton(withTitle: "知道了")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        InputTap.shared.stop()
    }

    private func anyFeatureEnabled() -> Bool {
        settings.trafficLightEnabled || settings.cutEnabled || settings.dockEnabled
    }

    private func updateTap() {
        if anyFeatureEnabled(), Permissions.isAccessibilityTrusted {
            _ = InputTap.shared.start()
        } else {
            InputTap.shared.stop()
        }
    }

    /// 用户在系统设置里勾选授权后，应用不重启也要立刻接管。
    private func startPermissionWatch() {
        guard permissionTimer == nil, !Permissions.isAccessibilityTrusted else { return }
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            if Permissions.isAccessibilityTrusted {
                timer.invalidate()
                self.permissionTimer = nil
                self.updateTap()
                NotificationCenter.default.post(name: .permissionStateChanged, object: nil)
            }
        }
        permissionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func handleSettingsChange() {
        updateTap()
        guard anyFeatureEnabled(), !Permissions.isAccessibilityTrusted else { return }
        startPermissionWatch()
        guard !permissionRequested else { return }
        permissionRequested = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            Permissions.requestAccessibility()
        }
    }

    private func openSettings(pageIndex: Int = 0) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(settings: settings)
        }
        settingsWindowController?.present(pageIndex: pageIndex)
    }
}
