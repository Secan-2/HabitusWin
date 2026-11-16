import AppKit
import ApplicationServices

/// Finder 的 ⌘X 剪切。
/// 键盘事件由共享的 InputTap 统一分发，这里只负责判定与改写动作。
final class CutPasteModule {
    private let settings: AppSettings
    private var frontmostBundleID: String?

    /// 剪切发生时剪贴板的变更计数。计数一旦被别的复制操作改写，剪切状态自动失效。
    private var cutChangeCount: Int?

    private static let finderBundleID = "com.apple.finder"
    private static let keyC: CGKeyCode = 8
    private static let keyV: CGKeyCode = 9
    private static let keyX: CGKeyCode = 7

    init(settings: AppSettings) {
        self.settings = settings
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontmostAppChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        InputTap.shared.addKeyDownHandler { [weak self] code, flags in
            self?.handleKeyDown(code: code, flags: flags) ?? false
        }
    }

    func start() {}

    func reconfigure() {}

    @objc private func frontmostAppChanged() {
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    private func handleKeyDown(code: CGKeyCode, flags: CGEventFlags) -> Bool {
        guard settings.cutEnabled else { return false }
        guard frontmostBundleID == Self.finderBundleID else { return false }
        guard flags.contains(.maskCommand),
              !flags.contains(.maskAlternate),
              !flags.contains(.maskControl),
              !flags.contains(.maskShift) else { return false }

        if code == Self.keyX {
            guard !isFinderEditingText() else { return false }
            // 只有确认没有选中项时才放行；判断不了就照常接管，避免误伤。
            if finderHasSelection() == false { return false }
            // 按下即给反馈，不依赖后面那次复制往返的成败。
            SoundPlayer.shared.play(settings.cutSound, volume: settings.cutVolume)
            DispatchQueue.main.async { [weak self] in self?.performCut() }
            return true
        }

        if code == Self.keyV {
            guard let cutChangeCount, cutChangeCount == NSPasteboard.general.changeCount else {
                return false
            }
            guard !isFinderEditingText() else { return false }
            self.cutChangeCount = nil
            DispatchQueue.main.async { [weak self] in self?.performMove() }
            return true
        }

        return false
    }

    /// 读不到就返回 nil，调用方按「照常接管」处理。
    private func finderHasSelection() -> Bool? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let focused = AX.element(axApp, kAXFocusedUIElementAttribute) else { return nil }

        var node: AXUIElement? = focused
        for _ in 0..<3 {
            guard let current = node else { break }
            if let value = AX.attr(current, kAXSelectedChildrenAttribute) {
                let children = value as? [AXUIElement] ?? []
                return !children.isEmpty
            }
            if let value = AX.attr(current, "AXSelectedRows") {
                let rows = value as? [AXUIElement] ?? []
                return !rows.isEmpty
            }
            node = AX.element(current, kAXParentAttribute)
        }
        return nil
    }

    private func isFinderEditingText() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let focused = AX.element(axApp, kAXFocusedUIElementAttribute) else { return false }
        let role = AX.string(focused, kAXRoleAttribute) ?? ""
        return role == "AXTextField" || role == "AXTextArea" || role == "AXSearchField"
    }

    private func performCut() {
        guard settings.cutEnabled,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.finderBundleID else {
            return
        }
        let pasteboard = NSPasteboard.general
        let baseline = pasteboard.changeCount
        InputTap.shared.postKey(Self.keyC, flags: .maskCommand)
        waitForPasteboard(baseline: baseline, attemptsLeft: 12)
    }

    private func waitForPasteboard(baseline: Int, attemptsLeft: Int) {
        guard attemptsLeft > 0 else { return }
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount == baseline else {
            completeCut()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { [weak self] in
            self?.waitForPasteboard(baseline: baseline, attemptsLeft: attemptsLeft - 1)
        }
    }

    private func completeCut() {
        let pasteboard = NSPasteboard.general
        guard let items = pasteboard.pasteboardItems,
              items.contains(where: { $0.types.contains(.fileURL) }) else {
            return
        }
        cutChangeCount = pasteboard.changeCount
    }

    private func performMove() {
        InputTap.shared.postKey(Self.keyV, flags: [.maskCommand, .maskAlternate])
    }
}
