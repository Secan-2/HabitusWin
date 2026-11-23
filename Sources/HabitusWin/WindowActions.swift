import AppKit
import ApplicationServices
import Darwin

final class WindowActions {
    private static var savedFrames: [pid_t: CGRect] = [:]

    static func apply(_ action: WindowButtonAction, pid: pid_t, window: AXUIElement?) {
        switch action {
        case .none:
            return
        case .closeWindow:
            close(window)
        case .quitApp:
            quit(pid: pid, window: window)
        case .minimizeWindow:
            if let window {
                AX.setBool(window, kAXMinimizedAttribute, true)
            }
        case .hideApp:
            _ = NSRunningApplication(processIdentifier: pid)?.hide()
        case .zoomWindow:
            zoom(pid: pid, window: window)
        case .toggleFullScreen:
            toggleFullScreen(window)
        }
    }

    // MARK: - 关闭与退出

    static func close(_ window: AXUIElement?) {
        guard let window, let button = AX.element(window, kAXCloseButtonAttribute) else { return }
        AX.perform(button, kAXPressAction)
    }

    /// 退出应用。
    /// 多窗口时只关当前这一个，避免一颗红按钮带走用户全部工作。
    /// 单窗口时先发退出请求，应用不退再逐级升级，避免 Dock 上留下运行指示。
    static func quit(pid: pid_t, window: AXUIElement?) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }

        let all = realWindows(of: pid).count
        let users = userWindows(of: pid).count
        Log.write("quit pid=\(pid) name=\(app.localizedName ?? "?") all=\(all) user=\(users)")

        if users > 1 {
            Log.write("quit -> 多窗口，改为关窗")
            close(window)
            return
        }

        // 用合成的 ⌘Q 代替 Apple Event 退出请求。
        // 前者走应用自己的菜单处理，不受自动化授权限制，也不会因为对方不响应而阻塞。
        Log.write("send cmd-Q")
        InputTap.shared.postKey(12, flags: .maskCommand)
        escalate(pid: pid, checksLeft: 6)
    }

    /// 每 0.2 秒用 kill(pid, 0) 探活，不做任何辅助功能调用。
    /// 应用真退出了，第一个周期就能收手；不退的才走到 1.2 秒后的强制收尾。
    private static func escalate(pid: pid_t, checksLeft: Int) {
        guard processAlive(pid) else {
            Log.write("gone after \(6 - checksLeft) ticks")
            return
        }
        guard checksLeft > 0 else {
            guard !hasBlockingDialog(pid: pid) else {
                Log.write("blocked by sheet, stop")
                return
            }
            finishOff(pid: pid)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            escalate(pid: pid, checksLeft: checksLeft - 1)
        }
    }

    private static func processAlive(_ pid: pid_t) -> Bool {
        errno = 0
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    private static func finishOff(pid: pid_t) {
        guard processAlive(pid) else {
            Log.write("finishOff: already gone")
            return
        }
        errno = 0
        let term = kill(pid, SIGTERM)
        Log.write("sigterm ret=\(term) errno=\(errno)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard processAlive(pid) else {
                Log.write("exit after sigterm")
                return
            }
            errno = 0
            let hard = kill(pid, SIGKILL)
            Log.write("sigkill ret=\(hard) errno=\(errno)")
        }
    }

    private static func hasBlockingDialog(pid: pid_t) -> Bool {
        for window in realWindows(of: pid) {
            if let sheets = AX.attr(window, "AXSheets") as? [AXUIElement], !sheets.isEmpty {
                return true
            }
            if AX.string(window, kAXSubroleAttribute) == "AXSheet" {
                return true
            }
        }
        return false
    }

    static func zoom(pid: pid_t, window: AXUIElement?) {
        guard let window, let current = AX.frame(window) else { return }
        guard let screen = Geometry.screen(containingAX: current) else { return }

        var target = Geometry.axRect(fromCocoa: screen.visibleFrame)
        target = target.insetBy(dx: 0, dy: 0)

        let alreadyZoomed = abs(current.minX - target.minX) < 3
            && abs(current.minY - target.minY) < 3
            && abs(current.width - target.width) < 3
            && abs(current.height - target.height) < 3

        if alreadyZoomed, let previous = savedFrames[pid] {
            AX.setFrame(window, previous)
            savedFrames[pid] = nil
        } else {
            savedFrames[pid] = current
            AX.setFrame(window, target)
        }
    }

    static func toggleFullScreen(_ window: AXUIElement?) {
        guard let window else { return }
        let key = "AXFullScreen"
        let current = AX.bool(window, key) ?? false
        AX.setBool(window, key, !current)
    }

    static func minimize(_ window: AXUIElement?, _ flag: Bool = true) -> Bool {
        guard let window else { return false }
        return AX.setBool(window, kAXMinimizedAttribute, flag)
    }

    static func windows(of pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        // 目标应用忙的时候，默认的辅助功能消息超时能卡住我们好几秒
        AXUIElementSetMessagingTimeout(app, 0.4)
        guard let value = AX.attr(app, kAXWindowsAttribute) else { return [] }
        return (value as? [AXUIElement]) ?? []
    }

    /// 只保留真正给用户看的窗口。有些应用会把零尺寸的隐藏窗口塞进 AXWindows，
    /// 用它判断「有几个窗口」会误判成多窗口，从而把退出降级成关窗。
    static func userWindows(of pid: pid_t) -> [AXUIElement] {
        realWindows(of: pid).filter { window in
            let subrole = AX.string(window, kAXSubroleAttribute) ?? ""
            if subrole == "AXUnknown" { return false }
            guard let frame = AX.frame(window) else { return false }
            return frame.width >= 100 && frame.height >= 100
        }
    }

    /// 访达会把桌面作为一个 AXScrollArea / AXDesktop 放进窗口列表，
    /// 它不是可最小化的真实窗口，参与判断会让「全部最小化」永远为假。
    static func realWindows(of pid: pid_t) -> [AXUIElement] {
        windows(of: pid).filter { window in
            let subrole = AX.string(window, kAXSubroleAttribute) ?? ""
            return subrole != "AXDesktop"
        }
    }

    static func focusedWindow(of pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        return AX.element(app, kAXFocusedWindowAttribute)
    }
}
