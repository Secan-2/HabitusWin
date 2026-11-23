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

        if realWindows(of: pid).count > 1 {
            close(window)
            return
        }

        app.terminate()
        escalate(app: app, pid: pid, checksLeft: 5)
    }

    /// 每秒三次检查，1.5 秒仍未退出才干预。
    /// 只要应用还有窗口，说明可能停在保存确认上，此时不打断用户。
    private static func escalate(app: NSRunningApplication, pid: pid_t, checksLeft: Int) {
        guard checksLeft > 0 else {
            guard realWindows(of: pid).isEmpty else { return }
            kill(pid, SIGTERM)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if !app.isTerminated { kill(pid, SIGKILL) }
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard !app.isTerminated else { return }
            escalate(app: app, pid: pid, checksLeft: checksLeft - 1)
        }
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
        guard let value = AX.attr(app, kAXWindowsAttribute) else { return [] }
        return (value as? [AXUIElement]) ?? []
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
