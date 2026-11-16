import AppKit

final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let settings: AppSettings
    private let onOpenSettings: () -> Void

    init(settings: AppSettings, onOpenSettings: @escaping () -> Void) {
        self.settings = settings
        self.onOpenSettings = onOpenSettings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = Self.makeStatusImage()
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        buildMenu()
    }

    /// 菜单栏图标：一个窗口外框，里面三颗圆点，对应窗口左上角的红黄绿。
    /// 作为模板图交给系统着色，跟着菜单栏明暗自动变黑白。
    /// 用位图代表按 scale 渲染，避免在 Retina 上被放大一次。
    static func makeStatusImage(scale: CGFloat = 2) -> NSImage {
        let pointSize = NSSize(width: 21, height: 18)
        let pixelWidth = max(1, Int((pointSize.width * scale).rounded()))
        let pixelHeight = max(1, Int((pointSize.height * scale).rounded()))

        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: pixelWidth,
                                         pixelsHigh: pixelHeight,
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0) else {
            return NSImage(size: pointSize)
        }
        rep.size = pointSize

        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = context
            context.cgContext.setShouldAntialias(true)
            drawMark()
            context.flushGraphics()
        }
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: pointSize)
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }

    private static func drawMark() {
        NSColor.black.setStroke()
        NSColor.black.setFill()

        // 窗口外框：略宽于高，接近真实窗口的比例，不然会读成一个圆角方块
        let frameRect = NSRect(x: 1.6, y: 2.6, width: 17.8, height: 12.8)
        let frame = NSBezierPath(roundedRect: frameRect, xRadius: 2.8, yRadius: 2.8)
        frame.lineWidth = 0.95
        frame.stroke()

        // 框内三颗实心圆，按框高放大，避免显得空
        let diameter: CGFloat = 3.4
        let gap: CGFloat = 1.15
        let totalWidth = diameter * 3 + gap * 2
        var x = frameRect.midX - totalWidth / 2
        let y = frameRect.midY - diameter / 2

        for _ in 0..<3 {
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: diameter, height: diameter)).fill()
            x += diameter + gap
        }
    }

    private func buildMenu() {
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let trafficItem = NSMenuItem(title: "接管窗口红绿灯", action: #selector(toggleTrafficLight), keyEquivalent: "")
        trafficItem.target = self
        trafficItem.state = settings.trafficLightEnabled ? .on : .off
        trafficItem.tag = 101
        menu.addItem(trafficItem)

        let cutItem = NSMenuItem(title: "Finder ⌘X 剪切", action: #selector(toggleCut), keyEquivalent: "")
        cutItem.target = self
        cutItem.state = settings.cutEnabled ? .on : .off
        cutItem.tag = 102
        menu.addItem(cutItem)

        let dockItem = NSMenuItem(title: "Dock 点击最小化", action: #selector(toggleDock), keyEquivalent: "")
        dockItem.target = self
        dockItem.state = settings.dockEnabled ? .on : .off
        dockItem.tag = 103
        menu.addItem(dockItem)

        menu.addItem(.separator())

        let permissionItem = NSMenuItem(title: "辅助功能权限…", action: #selector(openPermission), keyEquivalent: "")
        permissionItem.target = self
        menu.addItem(permissionItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 HabitusWin", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func refreshStates() {
        for item in menu.items {
            switch item.tag {
            case 101: item.state = settings.trafficLightEnabled ? .on : .off
            case 102: item.state = settings.cutEnabled ? .on : .off
            case 103: item.state = settings.dockEnabled ? .on : .off
            default: break
            }
        }
    }

    @objc private func handleClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            refreshStates()
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            onOpenSettings()
        }
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func toggleTrafficLight() {
        settings.trafficLightEnabled.toggle()
    }

    @objc private func toggleCut() {
        settings.cutEnabled.toggle()
    }

    @objc private func toggleDock() {
        settings.dockEnabled.toggle()
    }

    @objc private func openPermission() {
        Permissions.openAccessibilitySettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
