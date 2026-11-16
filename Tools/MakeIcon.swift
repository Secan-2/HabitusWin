import AppKit

// 生成 1024x1024 应用图标：深色圆角底 + 三个红绿灯圆点
let size = 1024.0
let canvas = NSRect(x: 0, y: 0, width: size, height: size)

let image = NSImage(size: canvas.size)
image.lockFocus()

NSColor.clear.setFill()
canvas.fill()

let body = NSBezierPath(roundedRect: canvas.insetBy(dx: 78, dy: 78), xRadius: 190, yRadius: 190)
NSColor(srgbRed: 0.12, green: 0.12, blue: 0.14, alpha: 1).setFill()
body.fill()

NSColor(white: 1, alpha: 0.10).setStroke()
body.lineWidth = 5
body.stroke()

let dots: [(CGFloat, NSColor)] = [
    (292, NSColor(srgbRed: 1.00, green: 0.373, blue: 0.341, alpha: 1)),
    (512, NSColor(srgbRed: 0.996, green: 0.737, blue: 0.180, alpha: 1)),
    (732, NSColor(srgbRed: 0.157, green: 0.784, blue: 0.251, alpha: 1))
]

for (x, color) in dots {
    let rect = NSRect(x: x - 100, y: 512 - 100, width: 200, height: 200)
    let circle = NSBezierPath(ovalIn: rect)
    color.setFill()
    circle.fill()

    NSColor(white: 0, alpha: 0.18).setStroke()
    circle.lineWidth = 4
    circle.stroke()
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("render failed\n".utf8))
    exit(1)
}

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/AppIcon_1024.png"
try png.write(to: URL(fileURLWithPath: output))
print(output)
