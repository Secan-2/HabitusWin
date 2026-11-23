import AppKit
import ApplicationServices
import Combine

enum LightKind: String, CaseIterable {
    case close
    case minimize
    case zoom

    init?(subrole: String) {
        switch subrole {
        case "AXCloseButton": self = .close
        case "AXMinimizeButton": self = .minimize
        case "AXFullScreenButton", "AXZoomButton": self = .zoom
        default: return nil
        }
    }
}

/// 红绿灯改行为的实现：不画任何覆盖层，直接吞掉落在按钮上的点击，再执行映射后的动作。
/// 覆盖层方案会在拖动窗口时掉帧留下残影，吞事件方案没有可渲染的残留物。
/// 悬停时系统仍会正常显示按钮上的叉、横线、三角，代价只是被吞掉的那次点击没有按下态。
final class WindowClickModule {
    private let settings: AppSettings

    private var cachedPID: pid_t = 0
    private var cachedWindow: AXUIElement?
    private var cachedFrame: CGRect = .null
    private var cacheStamp: CFTimeInterval = 0

    private let excludedBundleIDs: Set<String> = [
        "com.apple.dock",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.WindowManager",
        "com.apple.systemuiserver",
        "com.apple.screencaptureui",
        "com.apple.Spotlight"
    ]

    init(settings: AppSettings) {
        self.settings = settings

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(invalidateCache),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        InputTap.shared.addMouseDownHandler { [weak self] point, flags in
            self?.handleMouseDown(at: point, flags: flags) ?? false
        }

        InputTap.shared.addMouseUpHandler { [weak self] _ in
            self?.invalidateCache()
            return false
        }
    }

    @objc private func invalidateCache() {
        cacheStamp = 0
    }

    private func handleMouseDown(at point: CGPoint, flags: CGEventFlags) -> Bool {
        guard settings.trafficLightEnabled else { return false }
        guard !flags.contains(.maskCommand),
              !flags.contains(.maskAlternate),
              !flags.contains(.maskControl) else { return false }

        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != getpid(),
              let bundleID = front.bundleIdentifier,
              !excludedBundleIDs.contains(bundleID) else { return false }

        let pid = front.processIdentifier
        let frame = focusedWindowFrame(pid: pid)
        guard !frame.isNull else { return false }

        // 便宜的几何前置判断，绝大多数点击在这一步就返回。
        guard point.x >= frame.minX - 2, point.x <= frame.minX + 92,
              point.y >= frame.minY - 2, point.y <= frame.minY + 34 else { return false }

        let element = AX.element(at: point)
        let subrole = element.flatMap { AX.string($0, kAXSubroleAttribute) } ?? ""

        guard let window = element.flatMap(enclosingWindow) ?? cachedWindow else { return false }

        // 先按命中元素的子角色判断。少数应用命中会返回 AXUnknown，
        // 例如 QQ 音乐，此时退回用窗口自身三个按钮的矩形做几何比对。
        let kind: LightKind
        if let bySubrole = LightKind(subrole: subrole) {
            kind = bySubrole
        } else if let byFrame = lightKind(at: point, in: window) {
            Log.write("hit fallback by frame sub=\(subrole) kind=\(byFrame.rawValue)")
            kind = byFrame
        } else {
            return false
        }
        guard AX.bool(window, "AXFullScreen") != true else { return false }

        let action = settings.action(for: kind)
        // 访达这类系统常驻应用保持系统原生行为，不接管退出，点击原样交给系统。
        if action == .quitApp, isSystemResident(app: front, bundleID: bundleID) {
            return false
        }

        Log.write("click app=\(bundleID) sub=\(subrole) action=\(action.rawValue) user=\(WindowActions.userWindows(of: pid).count)")
        WindowActions.apply(action, pid: pid, window: window)
        invalidateCache()
        return true
    }

    /// 系统常驻进程没有「退出」语义，退出等于关掉全部窗口再被 launchd 拉起。
    /// 没有 Dock 图标的常驻应用也归入此类，用红按钮移除菜单栏图标并不合适。
    private func isSystemResident(app: NSRunningApplication, bundleID: String) -> Bool {
        if bundleID == "com.apple.finder" { return true }
        return app.activationPolicy != .regular
    }

    // MARK: - 窗口定位

    private func focusedWindowFrame(pid: pid_t) -> CGRect {
        let now = CACurrentMediaTime()
        if pid == cachedPID, now - cacheStamp < 1.2, !cachedFrame.isNull {
            return cachedFrame
        }
        let appElement = AXUIElementCreateApplication(pid)
        guard let window = AX.element(appElement, kAXFocusedWindowAttribute),
              let frame = AX.frame(window) else {
            cachedPID = pid
            cachedFrame = .null
            cachedWindow = nil
            cacheStamp = now
            return .null
        }
        cachedPID = pid
        cachedWindow = window
        cachedFrame = frame
        cacheStamp = now
        return frame
    }

    /// 用窗口自带的三个按钮矩形做兜底判断，命中范围外扩 4pt 容错。
    private func lightKind(at point: CGPoint, in window: AXUIElement) -> LightKind? {
        let candidates: [(String, LightKind)] = [
            (kAXCloseButtonAttribute, .close),
            (kAXMinimizeButtonAttribute, .minimize),
            (kAXFullScreenButtonAttribute, .zoom),
            ("AXZoomButton", .zoom)
        ]
        for (attribute, kind) in candidates {
            guard let button = AX.element(window, attribute), let frame = AX.frame(button) else { continue }
            if frame.insetBy(dx: -4, dy: -4).contains(point) {
                return kind
            }
        }
        return nil
    }

    private func enclosingWindow(of element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element
        for _ in 0..<8 {
            guard let node = current else { return nil }
            if AX.string(node, kAXRoleAttribute) == "AXWindow" { return node }
            current = AX.element(node, kAXParentAttribute)
        }
        return nil
    }
}
