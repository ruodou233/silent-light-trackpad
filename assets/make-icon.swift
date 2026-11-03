// Draws AppIcon.icns: a light touch on a trackpad, with no vibration rings.
// swift assets/make-icon.swift /tmp/AppIcon.iconset && iconutil -c icns /tmp/AppIcon.iconset -o assets/AppIcon.icns
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func drawIcon() {
    // Apple's macOS icon grid: an 824-point body with a 185-point corner radius on a 1024 canvas.
    let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGradient(starting: NSColor(srgbRed: 0.47, green: 0.55, blue: 0.98, alpha: 1),
               ending: NSColor(srgbRed: 0.27, green: 0.32, blue: 0.80, alpha: 1))!.draw(in: body, angle: -90)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.22)
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.shadowBlurRadius = 28
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor(white: 1, alpha: 0.96).setFill()
    NSBezierPath(roundedRect: NSRect(x: 212, y: 332, width: 600, height: 380), xRadius: 56, yRadius: 56).fill()
    NSGraphicsContext.restoreGraphicsState()

    let accent = NSColor(srgbRed: 0.31, green: 0.37, blue: 0.86, alpha: 1)
    accent.withAlphaComponent(0.18).setFill()
    NSBezierPath(ovalIn: NSRect(x: 590 - 92, y: 480 - 92, width: 184, height: 184)).fill()
    accent.setFill()
    NSBezierPath(ovalIn: NSRect(x: 590 - 50, y: 480 - 50, width: 100, height: 100)).fill()
}

for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let pixels = points * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(pixels) / 1024)
    transform.concat()
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
}
