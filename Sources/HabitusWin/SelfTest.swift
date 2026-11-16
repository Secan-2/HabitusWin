import AppKit

final class BackgroundHostView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
    }
}

enum SelfTest {
    static func run() {
        let settings = AppSettings.shared

        let diagnostics = Permissions.diagnostics()
        print("trusted: \(diagnostics.trusted) ax: \(diagnostics.axErrorText)")
        print("path: \(diagnostics.path)")
        print("signature: \(Permissions.signatureSummary())")
        print("tap: running=\(InputTap.shared.isRunning) error=\(InputTap.shared.lastError ?? "-")")
        let tapStarted = InputTap.shared.start()
        print("tap start attempt: \(tapStarted) error=\(InputTap.shared.lastError ?? "-")")
        InputTap.shared.stop()
        print("sound: \(Bundle.main.url(forResource: "Snip", withExtension: "wav")?.lastPathComponent ?? "missing")")

        // 按 16 倍渲染，位图与画布 1:1，能看出真实的矢量边缘
        let previewScale: CGFloat = 16
        let icon = StatusItemController.makeStatusImage(scale: previewScale)
        let canvas = NSSize(width: icon.size.width * previewScale, height: icon.size.height * previewScale)
        let big = NSImage(size: canvas)
        big.lockFocus()
        NSColor(white: 0.93, alpha: 1).setFill()
        NSRect(origin: .zero, size: canvas).fill()
        icon.draw(in: NSRect(origin: .zero, size: canvas))
        big.unlockFocus()
        if let tiff = big.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: "/tmp/statusicon.png"))
            print("rendered /tmp/statusicon.png")
        }

        if let front = NSWorkspace.shared.frontmostApplication {
            let appElement = AXUIElementCreateApplication(front.processIdentifier)
            let window = AX.element(appElement, kAXFocusedWindowAttribute)
            print("frontmost: \(front.localizedName ?? "?") window=\(window != nil ? "yes" : "no")")
            if let window {
                for (name, attribute) in [("close", kAXCloseButtonAttribute),
                                          ("minimize", kAXMinimizeButtonAttribute),
                                          ("zoom", kAXZoomButtonAttribute)] {
                    let element = AX.element(window, attribute)
                    let frame = element.flatMap(AX.frame)
                    print("  \(name): frame=\(frame.map { "\($0)" } ?? "nil")")
                    if let frame, let hit = AX.element(at: CGPoint(x: frame.midX, y: frame.midY)) {
                        print("    hit role=\(AX.string(hit, kAXRoleAttribute) ?? "-") subrole=\(AX.string(hit, kAXSubroleAttribute) ?? "-")")
                    } else {
                        print("    hit: nil")
                    }
                }
            }
        }

        let controller = SettingsWindowController(settings: settings)
        guard let window = controller.window, let content = window.contentView else { return }
        print("window frame: \(window.frame)")
        print("content size: \(content.bounds.size)")

        for index in 0..<4 {
            controller.testSelectPage(index)
            content.layoutSubtreeIfNeeded()
            let child = content.subviews.first
            print("page \(index): frame \(child?.frame ?? .zero)")
            if let child {
                let host = BackgroundHostView(frame: NSRect(origin: .zero, size: content.bounds.size))
                child.removeFromSuperview()
                child.translatesAutoresizingMaskIntoConstraints = true
                child.frame = host.bounds
                child.autoresizingMask = [.width, .height]
                host.addSubview(child)
                host.layoutSubtreeIfNeeded()
                save(host, to: "/tmp/tp_page_\(index).png", scale: 1)
            }
        }
        print("selftest done")
    }

    private static func dump(_ view: NSView, depth: Int) {
        guard depth <= 7 else { return }
        let pad = String(repeating: "  ", count: depth)
        let name = String(describing: type(of: view))
        let label = (view as? NSTextField)?.stringValue.prefix(12) ?? ""
        print("\(pad)\(name) \(Int(view.frame.origin.x)),\(Int(view.frame.origin.y)) \(Int(view.frame.width))x\(Int(view.frame.height)) hidden=\(view.isHidden) \(label)")
        for sub in view.subviews {
            dump(sub, depth: depth + 1)
        }
    }

    private static func save(_ view: NSView, to path: String, scale: CGFloat) {
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1 else {
            print("skip render \(path)")
            return
        }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            print("no rep \(path)")
            return
        }
        view.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            print("no png \(path)")
            return
        }
        try? data.write(to: URL(fileURLWithPath: path))
        print("rendered \(path) \(Int(bounds.width))x\(Int(bounds.height))")
    }
}
