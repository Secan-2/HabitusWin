import AppKit

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class WrappingLabel: NSTextField {
    override func layout() {
        super.layout()
        guard bounds.width > 1 else { return }
        // 只允许向下收紧，避免首次布局时的临时宽度把换行宽度顶大。
        if preferredMaxLayoutWidth <= 0 || bounds.width < preferredMaxLayoutWidth {
            preferredMaxLayoutWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
    }
}

final class CardView: NSView {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let fill = isDark ? NSColor(white: 0.17, alpha: 1) : NSColor.white
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        fill.setFill()
        path.fill()
        NSColor.separatorColor.withAlphaComponent(isDark ? 0.35 : 0.7).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

final class SettingsWindowController: NSWindowController, NSToolbarDelegate {
    private let settings: AppSettings
    private let container = NSView()
    private let segmented = NSSegmentedControl(labels: ["红绿灯", "剪切", "Dock", "通用"],
                                               trackingMode: .selectOne,
                                               target: nil,
                                               action: nil)
    private var pages: [NSView] = []
    private var permissionLabel: NSTextField?
    private var pathLabel: NSTextField?
    private var axLabel: NSTextField?
    private var tapLabel: NSTextField?
    private var hintLabel: NSTextField?

    init(settings: AppSettings) {
        self.settings = settings
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 640),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        super.init(window: window)
        window.title = "HabitusWin"
        window.isReleasedWhenClosed = false
        window.center()
        buildToolbar()
        buildPages()
        selectPage(0)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(refreshPermissionState),
                                               name: NSApplication.didBecomeActiveNotification,
                                               object: nil)
    }

    required init?(coder: NSCoder) { nil }

    func present(pageIndex: Int = 0) {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        selectPage(pageIndex)
        refreshPermissionState()
        window.makeKeyAndOrderFront(nil)
    }

    func testSelectPage(_ index: Int) {
        selectPage(index)
    }

    // MARK: - Toolbar

    private func buildToolbar() {
        segmented.target = self
        segmented.action = #selector(segmentChanged)
        segmented.selectedSegment = 0

        let toolbar = NSToolbar(identifier: "HabitusWinSettings")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window?.toolbar = toolbar
        window?.toolbarStyle = .preference
    }

    @objc private func segmentChanged() {
        selectPage(segmented.selectedSegment)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, NSToolbarItem.Identifier("tabs"), .flexibleSpace]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, NSToolbarItem.Identifier("tabs"), .flexibleSpace]
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard itemIdentifier.rawValue == "tabs" else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.view = segmented
        item.label = "分区"
        return item
    }

    // MARK: - Pages

    private func buildPages() {
        pages = [makeTrafficLightPage(), makeCutPage(), makeDockPage(), makeGeneralPage()]
        window?.contentView = container
    }

    private func selectPage(_ index: Int) {
        guard index >= 0, index < pages.count else { return }
        segmented.selectedSegment = index
        for view in container.subviews {
            view.removeFromSuperview()
        }
        let page = pages[index]
        page.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(page)
        NSLayoutConstraint.activate([
            page.topAnchor.constraint(equalTo: container.topAnchor),
            page.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            page.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    // MARK: - Layout primitives

    private func makePage(_ sections: [(String?, [NSView])]) -> NSView {
        let document = FlippedView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -22),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -22)
        ])

        for (title, rows) in sections {
            let block = NSStackView()
            block.orientation = .vertical
            block.alignment = .leading
            block.spacing = 8

            if let title {
                let label = NSTextField(labelWithString: title)
                label.font = .systemFont(ofSize: 11, weight: .semibold)
                label.textColor = .secondaryLabelColor
                block.addArrangedSubview(label)
                label.widthAnchor.constraint(equalTo: block.widthAnchor).isActive = true
            }

            let card = CardView()
            card.translatesAutoresizingMaskIntoConstraints = false
            let inner = NSStackView()
            inner.orientation = .vertical
            inner.alignment = .leading
            inner.spacing = 12
            inner.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(inner)

            NSLayoutConstraint.activate([
                inner.topAnchor.constraint(equalTo: card.topAnchor, constant: 13),
                inner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 15),
                inner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -15),
                inner.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -13)
            ])

            for row in rows {
                inner.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true
            }

            block.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: block.widthAnchor).isActive = true

            stack.addArrangedSubview(block)
            block.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = document
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        document.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])
        return scrollView
    }

    private func row(_ title: String, subtitle: String? = nil, control: NSView) -> NSView {
        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        if !title.isEmpty {
            let titleLabel = NSTextField(labelWithString: title)
            titleLabel.font = .systemFont(ofSize: 13)
            textStack.addArrangedSubview(titleLabel)
        }

        if let subtitle {
            let sub = WrappingLabel(wrappingLabelWithString: subtitle)
            sub.font = .systemFont(ofSize: 11)
            sub.textColor = .secondaryLabelColor
            sub.preferredMaxLayoutWidth = 320
            textStack.addArrangedSubview(sub)
            sub.widthAnchor.constraint(equalTo: textStack.widthAnchor).isActive = true
        }

        control.setContentHuggingPriority(.init(800), for: .horizontal)
        control.setContentCompressionResistancePriority(.init(800), for: .horizontal)

        let rowStack = NSStackView(views: [textStack, control])
        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY
        rowStack.spacing = 16
        rowStack.distribution = .fill
        rowStack.setContentHuggingPriority(.init(999), for: .vertical)
        rowStack.setContentCompressionResistancePriority(.init(999), for: .vertical)
        textStack.setContentHuggingPriority(.init(1), for: .horizontal)
        textStack.setContentCompressionResistancePriority(.init(200), for: .horizontal)
        textStack.setContentHuggingPriority(.init(999), for: .vertical)
        return rowStack
    }

    private func footnote(_ text: String) -> NSView {
        let label = WrappingLabel(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = 470
        label.setContentHuggingPriority(.init(999), for: .vertical)
        return label
    }

    private func switchControl(_ isOn: Bool, _ action: Selector) -> NSSwitch {
        let control = NSSwitch()
        control.state = isOn ? .on : .off
        control.target = self
        control.action = action
        return control
    }

    private func popUp(_ titles: [String], _ index: Int, _ action: Selector) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.addItems(withTitles: titles)
        button.selectItem(at: max(0, min(index, titles.count - 1)))
        button.target = self
        button.action = action
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        return button
    }

    // MARK: - Traffic light page

    private func makeTrafficLightPage() -> NSView {
        let toggle = switchControl(settings.trafficLightEnabled, #selector(toggleTrafficLight))

        let red = popUp(WindowButtonAction.allCases.map(\.title), index(of: settings.redAction), #selector(changeRed))
        let yellow = popUp(WindowButtonAction.allCases.map(\.title), index(of: settings.yellowAction), #selector(changeYellow))
        let green = popUp(WindowButtonAction.allCases.map(\.title), index(of: settings.greenAction), #selector(changeGreen))

        return makePage([
            ("接管", [
                row("接管窗口红绿灯",
                    subtitle: "在前台窗口的原生按钮位置上叠加外观一致的原生控件，关闭后完全交还系统。",
                    control: toggle)
            ]),
            ("按钮动作", [
                row("红色按钮", control: red),
                row("黄色按钮", control: yellow),
                row("绿色按钮", control: green),
                footnote("红色按钮设成「退出应用」时，访达这类系统常驻应用与没有 Dock 图标的菜单栏应用会保持系统原生行为，点击原样交给系统。"),
                footnote("应用还开着其它窗口时，点红色只关闭当前窗口，最后一个窗口才触发退出。")
            ]),
            ("说明", [
                footnote("红色设为「退出应用」不会替你保存文档，是否丢弃未保存改动由目标应用决定。"),
                footnote("绿色设为「缩放窗口」时使用可见桌面区域，与原生的按住 ⌥ 点击行为接近。"),
                footnote("自绘标题栏、或未向辅助功能暴露标准按钮的应用不会被接管，此时点击仍走系统默认行为。")
            ])
        ])
    }

    // MARK: - Cut page

    private func makeCutPage() -> NSView {
        let toggle = switchControl(settings.cutEnabled, #selector(toggleCut))
        let soundIndex = SoundPlayer.available.firstIndex(of: settings.cutSound) ?? 0
        let sound = popUp(SoundPlayer.available, soundIndex, #selector(changeSound))

        let slider = NSSlider(value: settings.cutVolume, minValue: 0, maxValue: 1, target: self, action: #selector(changeVolume))
        slider.isContinuous = true
        slider.widthAnchor.constraint(equalToConstant: 180).isActive = true

        let test = NSButton(title: "试听", target: self, action: #selector(previewSound))
        test.bezelStyle = .rounded

        let volumeRow = NSStackView(views: [slider, test])
        volumeRow.orientation = .horizontal
        volumeRow.spacing = 10
        volumeRow.setContentHuggingPriority(.init(800), for: .horizontal)

        return makePage([
            ("Finder 剪切", [
                row("启用 ⌘X 剪切", subtitle: "剪切时只做标记，粘贴时才真正移动文件。", control: toggle)
            ]),
            ("音效", [
                row("剪切音效", control: sound),
                row("音量", control: volumeRow)
            ]),
            ("说明", [
                footnote("移动动作由 Finder 自己完成，因此跨卷复制、同名冲突、权限提示与进度条都沿用系统行为。"),
                footnote("在 Finder 里重命名文件时按 ⌘X 会正常剪切文字，不会被拦截。"),
                footnote("复制其他内容后，之前的剪切标记自动失效。")
            ])
        ])
    }

    // MARK: - Dock page

    private func makeDockPage() -> NSView {
        let toggle = switchControl(settings.dockEnabled, #selector(toggleDock))
        let action = popUp(DockClickAction.allCases.map(\.title), index(of: settings.dockAction), #selector(changeDockAction))
        let precise = switchControl(settings.dockPrecise, #selector(togglePrecise))

        return makePage([
            ("再次点击 Dock 图标", [
                row("启用", subtitle: "对已在前台的应用再次点击其 Dock 图标时执行动作。", control: toggle),
                row("动作", control: action),
                row("仅在指针位于 Dock 上时触发", subtitle: "关闭后，用 ⌘Tab 切回同一应用也会触发。", control: precise)
            ]),
            ("说明", [
                footnote("全屏窗口无法直接最小化，此时点击 Dock 图标不会产生变化。"),
                footnote("无窗口的应用会被跳过，避免误隐藏后台应用。")
            ])
        ])
    }

    // MARK: - General page

    private func makeGeneralPage() -> NSView {
        let status = NSTextField(labelWithString: "")
        status.font = .systemFont(ofSize: 13)
        permissionLabel = status

        let path = WrappingLabel(wrappingLabelWithString: "")
        path.font = .systemFont(ofSize: 11)
        path.textColor = .secondaryLabelColor
        path.preferredMaxLayoutWidth = 470
        pathLabel = path

        let ax = WrappingLabel(wrappingLabelWithString: "")
        ax.font = .systemFont(ofSize: 11)
        ax.textColor = .secondaryLabelColor
        ax.preferredMaxLayoutWidth = 470
        axLabel = ax

        let tapState = WrappingLabel(wrappingLabelWithString: "")
        tapState.font = .systemFont(ofSize: 11)
        tapState.textColor = .secondaryLabelColor
        tapState.preferredMaxLayoutWidth = 470
        tapLabel = tapState

        let hint = WrappingLabel(wrappingLabelWithString: "")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .systemOrange
        hint.preferredMaxLayoutWidth = 470
        hint.isHidden = true
        hintLabel = hint

        let request = NSButton(title: "请求授权", target: self, action: #selector(requestPermission))
        request.bezelStyle = .rounded

        let open = NSButton(title: "打开系统设置", target: self, action: #selector(openPermission))
        open.bezelStyle = .rounded

        let reset = NSButton(title: "清理旧授权记录", target: self, action: #selector(resetPermission))
        reset.bezelStyle = .rounded

        let copy = NSButton(title: "复制诊断信息", target: self, action: #selector(copyDiagnostics))
        copy.bezelStyle = .rounded

        let buttons = NSStackView(views: [request, open])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.setContentHuggingPriority(.init(800), for: .horizontal)

        let secondButtons = NSStackView(views: [reset, copy])
        secondButtons.orientation = .horizontal
        secondButtons.spacing = 8
        secondButtons.setContentHuggingPriority(.init(800), for: .horizontal)

        let loginSwitch = NSSwitch()
        loginSwitch.state = LaunchAtLogin.isEnabled ? .on : .off
        loginSwitch.target = self
        loginSwitch.action = #selector(toggleLaunchAtLogin)

        let page = makePage([
            ("启动", [
                row("开机时自动启动",
                    subtitle: "登录系统后自动运行，只驻留菜单栏。应用需要放在「应用程序」文件夹里。",
                    control: loginSwitch)
            ]),
            ("开始使用", [
                footnote("三个功能默认全部关闭，装好后系统行为与原来完全一致。"),
                footnote("需要哪个功能，就到对应页面把开关打开。系统随后会弹出授权请求，点「打开系统设置」再勾选 HabitusWin。")
            ]),
            ("权限", [
                row("辅助功能", subtitle: "读取窗口按钮位置、执行窗口操作、拦截键盘事件都依赖这个权限。", control: status),
                row("", control: buttons),
                row("", control: secondButtons)
            ]),
            ("诊断", [
                path,
                ax,
                tapState,
                hint
            ]),
            ("隐私", [
                footnote("窗口位置与键盘事件仅在本机处理。退出与点击判定会写一条本地日志到 ~/Library/Logs/HabitusWin.log，只含应用名与耗时，不上传。"),
                footnote("菜单栏图标左键打开本窗口，右键打开开关菜单。"),
                footnote("版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知")")
            ])
        ])
        refreshPermissionState()
        return page
    }

    @objc private func refreshPermissionState() {
        let diagnostics = Permissions.diagnostics()

        permissionLabel?.stringValue = diagnostics.trusted ? "已授予" : "未授予"
        permissionLabel?.textColor = diagnostics.trusted ? .systemGreen : .systemOrange

        pathLabel?.stringValue = "运行位置：\(diagnostics.path)"
        axLabel?.stringValue = "AX 接口自检：\(diagnostics.axErrorText)　签名：\(Permissions.signatureSummary())"

        if InputTap.shared.isRunning {
            tapLabel?.stringValue = "输入监听：已启动"
            tapLabel?.textColor = .systemGreen
        } else {
            let reason = InputTap.shared.lastError ?? "所有功能均已关闭"
            tapLabel?.stringValue = "输入监听：未启动（\(reason)）"
            tapLabel?.textColor = .secondaryLabelColor
        }

        if diagnostics.translocated {
            hintLabel?.stringValue = "当前从只读临时路径运行，系统无法保存授权。先把应用拖进「应用程序」文件夹，再从那里打开。"
            hintLabel?.isHidden = false
        } else if !diagnostics.inApplications {
            hintLabel?.stringValue = "应用不在「应用程序」文件夹，授权会记到当前路径。建议移到 /Applications 后再授权。"
            hintLabel?.isHidden = false
        } else {
            hintLabel?.stringValue = ""
            hintLabel?.isHidden = true
        }
    }

    @objc private func requestPermission() {
        Permissions.requestAccessibility()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.refreshPermissionState()
        }
    }

    @objc private func resetPermission() {
        let alert = NSAlert()
        alert.messageText = "清理旧授权记录"
        alert.informativeText = "这会删除系统里保存的 HabitusWin 辅助功能记录，然后重新发起授权请求。如果之前勾选后反复跳回，通常就是旧记录残留导致的。"
        alert.addButton(withTitle: "清理并重新授权")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        _ = Permissions.resetAccessibility()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            Permissions.requestAccessibility()
            self?.refreshPermissionState()
        }
    }

    @objc private func copyDiagnostics() {
        let diagnostics = Permissions.diagnostics()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let location = diagnostics.translocated ? "AppTranslocation"
            : (diagnostics.inApplications ? "/Applications" : "其它路径")
        let text = """
        HabitusWin 诊断
        系统　　：\(ProcessInfo.processInfo.operatingSystemVersionString)
        版本　　：\(version)
        路径　　：\(diagnostics.path)
        位置　　：\(location)
        辅助功能：\(diagnostics.trusted ? "已授予" : "未授予")
        AX 自检　：\(diagnostics.axErrorText)
        签名　　：\(Permissions.signatureSummary())
        """

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        hintLabel?.textColor = .systemGreen
        hintLabel?.stringValue = "诊断信息已复制到剪贴板"
        hintLabel?.isHidden = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.refreshPermissionState()
        }
    }

    // MARK: - Actions

    private func index(of action: WindowButtonAction) -> Int {
        WindowButtonAction.allCases.firstIndex(of: action) ?? 0
    }

    private func index(of action: DockClickAction) -> Int {
        DockClickAction.allCases.firstIndex(of: action) ?? 0
    }

    @objc private func toggleTrafficLight(_ sender: NSSwitch) {
        settings.trafficLightEnabled = sender.state == .on
    }

    @objc private func changeRed(_ sender: NSPopUpButton) {
        settings.redAction = WindowButtonAction.allCases[sender.indexOfSelectedItem]
    }

    @objc private func changeYellow(_ sender: NSPopUpButton) {
        settings.yellowAction = WindowButtonAction.allCases[sender.indexOfSelectedItem]
    }

    @objc private func changeGreen(_ sender: NSPopUpButton) {
        settings.greenAction = WindowButtonAction.allCases[sender.indexOfSelectedItem]
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSSwitch) {
        let wanted = sender.state == .on
        if let message = LaunchAtLogin.set(wanted) {
            sender.state = wanted ? .off : .on
            let alert = NSAlert()
            alert.messageText = "无法修改开机启动"
            alert.informativeText = message
            alert.addButton(withTitle: "知道了")
            alert.runModal()
        }
    }

    @objc private func toggleCut(_ sender: NSSwitch) {
        settings.cutEnabled = sender.state == .on
    }

    @objc private func changeSound(_ sender: NSPopUpButton) {
        settings.cutSound = SoundPlayer.available[sender.indexOfSelectedItem]
        SoundPlayer.shared.preview(settings.cutSound, volume: settings.cutVolume)
    }

    @objc private func changeVolume(_ sender: NSSlider) {
        settings.cutVolume = sender.doubleValue
    }

    @objc private func previewSound() {
        SoundPlayer.shared.preview(settings.cutSound, volume: settings.cutVolume)
    }

    @objc private func toggleDock(_ sender: NSSwitch) {
        settings.dockEnabled = sender.state == .on
    }

    @objc private func changeDockAction(_ sender: NSPopUpButton) {
        settings.dockAction = DockClickAction.allCases[sender.indexOfSelectedItem]
    }

    @objc private func togglePrecise(_ sender: NSSwitch) {
        settings.dockPrecise = sender.state == .on
    }

    @objc private func openPermission() {
        Permissions.openAccessibilitySettings()
    }
}
