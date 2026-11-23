import AppKit
import ApplicationServices

/// 再次点击 Dock 图标时在「收起」与「展开」之间切换。
/// 用点击事件直接判断，不依赖「应用激活通知」。
final class DockClickModule {
    private let settings: AppSettings

    private var dockPID: pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
            .first?.processIdentifier
    }

    init(settings: AppSettings) {
        self.settings = settings
        InputTap.shared.addMouseDownHandler { [weak self] point, flags in
            self?.handleMouseDown(at: point, flags: flags) ?? false
        }
    }

    func start() {}

    private func handleMouseDown(at point: CGPoint, flags: CGEventFlags) -> Bool {
        guard settings.dockEnabled, settings.dockAction != .none else { return false }
        guard !flags.contains(.maskCommand),
              !flags.contains(.maskAlternate),
              !flags.contains(.maskShift),
              !flags.contains(.maskControl) else { return false }
        guard let dockPID else { return false }
        guard let element = AX.element(at: point), AX.pid(of: element) == dockPID else { return false }
        guard let item = dockItem(containing: element) else { return false }
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.bundleIdentifier != Bundle.main.bundleIdentifier else { return false }
        guard matches(item: item, app: front) else { return false }

        return toggle(app: front)
    }

    // MARK: - 收起与展开

    /// 方向只由真实窗口的 AX 最小化状态决定。
    /// 不能用 CGWindowList 统计在屏窗口，实测访达窗口最小化后仍被算作在屏；
    /// 也不能把 AXWindows 全量代入判断，访达的桌面窗口永远不可最小化。
    private func toggle(app: NSRunningApplication) -> Bool {
        let pid = app.processIdentifier
        let windows = WindowActions.userWindows(of: pid)
        guard !windows.isEmpty || app.isHidden else { return false }

        let allMinimized = !windows.isEmpty
            && windows.allSatisfy { AX.bool($0, kAXMinimizedAttribute) == true }

        if app.isHidden || allMinimized {
            return restore(app: app, windows: windows)
        }
        return collapse(app: app, windows: windows)
    }

    private func collapse(app: NSRunningApplication, windows: [AXUIElement]) -> Bool {
        switch settings.dockAction {
        case .none:
            return false
        case .minimizeFrontWindow:
            let target = windows.first { AX.bool($0, kAXMinimizedAttribute) != true } ?? windows.first
            return WindowActions.minimize(target)
        case .minimizeAllWindows:
            var changed = false
            for window in windows {
                changed = WindowActions.minimize(window) || changed
            }
            return changed
        case .hideApp:
            return app.hide()
        }
    }

    private func restore(app: NSRunningApplication, windows: [AXUIElement]) -> Bool {
        guard !windows.isEmpty || app.isHidden else { return false }

        if app.isHidden {
            _ = app.unhide()
        }
        for window in windows where AX.bool(window, kAXMinimizedAttribute) == true {
            _ = WindowActions.minimize(window, false)
        }
        app.activate(options: [.activateAllWindows])
        return true
    }

    // MARK: - 判定

    /// Dock 的图标是层层嵌套的容器，向上找到带 DockItem 子角色的节点。
    private func dockItem(containing element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element
        for _ in 0..<8 {
            guard let node = current else { return nil }
            let subrole = AX.string(node, kAXSubroleAttribute) ?? ""
            let role = AX.string(node, kAXRoleAttribute) ?? ""
            if subrole.contains("DockItem") {
                return node
            }
            if role == "AXButton", AX.string(node, kAXTitleAttribute) != nil {
                return node
            }
            current = AX.element(node, kAXParentAttribute)
        }
        return nil
    }

    private func matches(item: AXUIElement, app: NSRunningApplication) -> Bool {
        if let urlString = AX.string(item, "AXURL"),
           let url = URL(string: urlString),
           let appURL = app.bundleURL {
            return url.resolvingSymlinksInPath().path == appURL.resolvingSymlinksInPath().path
        }
        let title = AX.string(item, kAXTitleAttribute)
            ?? AX.string(item, kAXDescriptionAttribute)
            ?? ""
        guard !title.isEmpty, let name = app.localizedName else { return false }
        return title == name || title.hasPrefix(name)
    }
}
