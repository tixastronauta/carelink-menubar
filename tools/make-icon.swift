// Generates the CareLink Menubar app icon (original artwork, not MiniMed branding).
// Usage: xcrun swiftc tools/make-icon.swift -o build/make-icon && build/make-icon assets
// Writes assets/AppIcon.icns (via iconutil) and assets/AppIcon-1024.png for previews.
import AppKit

let accentLight = NSColor(srgbRed: 0.13, green: 0.66, blue: 0.69, alpha: 1)
let accentDark = NSColor(srgbRed: 0.04, green: 0.37, blue: 0.43, alpha: 1)

/// Draws the icon on a 1024-point canvas, scaled to `size` pixels.
func render(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    let scale = CGFloat(size) / 1024
    context.scaleBy(x: scale, y: scale)

    // macOS icon grid: 824×824 rounded square centred on 1024, with a soft shadow.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28,
                      color: NSColor.black.withAlphaComponent(0.30).cgColor)
    context.addPath(tilePath)
    context.setFillColor(accentDark.cgColor)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [accentLight.cgColor, accentDark.cgColor] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 200, y: 924), end: CGPoint(x: 824, y: 100), options: [])
    // Subtle top highlight for depth.
    let highlight = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [NSColor.white.withAlphaComponent(0.16).cgColor,
                                        NSColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(highlight, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])
    context.restoreGState()

    // White drop: straight sides tangent to the bottom circle, slightly rounded tip.
    let center = CGPoint(x: 512, y: 440), radius: CGFloat = 220
    let tip = CGPoint(x: 512, y: 830)
    let distance = tip.y - center.y
    let spread = CGFloat.pi / 2 - asin(radius / distance)   // angle from vertical to tangent point
    let left = CGPoint(x: center.x + radius * cos(.pi / 2 + spread), y: center.y + radius * sin(.pi / 2 + spread))
    let right = CGPoint(x: center.x + radius * cos(.pi / 2 - spread), y: center.y + radius * sin(.pi / 2 - spread))
    let drop = CGMutablePath()
    drop.move(to: CGPoint(x: tip.x - 6, y: tip.y - 10))
    drop.addLine(to: left)
    drop.addArc(center: center, radius: radius, startAngle: .pi / 2 + spread, endAngle: .pi / 2 - spread, clockwise: false)
    drop.addLine(to: CGPoint(x: tip.x + 6, y: tip.y - 10))
    drop.addQuadCurve(to: CGPoint(x: tip.x - 6, y: tip.y - 10), control: tip)
    drop.closeSubpath()
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -6), blur: 16,
                      color: NSColor.black.withAlphaComponent(0.18).cgColor)
    context.addPath(drop)
    context.setFillColor(NSColor.white.cgColor)
    context.fillPath()
    context.restoreGState()

    // Glucose line across the drop, clipped to it.
    context.saveGState()
    context.addPath(drop)
    context.clip()
    let line = CGMutablePath()
    let samples = 60
    for index in 0...samples {
        let t = CGFloat(index) / CGFloat(samples)
        let x = 270 + t * 484
        let y = 450 + 62 * sin(t * .pi * 2.1 + 0.5) + 18 * sin(t * .pi * 5.2)
        index == 0 ? line.move(to: CGPoint(x: x, y: y)) : line.addLine(to: CGPoint(x: x, y: y))
    }
    context.addPath(line)
    context.setStrokeColor(accentDark.cgColor)
    context.setLineWidth(28)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()
    context.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets")
let iconset = output.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (points, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for scale in scales {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        let data = render(size: points * scale).representation(using: .png, properties: [:])!
        try data.write(to: iconset.appendingPathComponent(name))
    }
}
try render(size: 1024).representation(using: .png, properties: [:])!
    .write(to: output.appendingPathComponent("AppIcon-1024.png"))
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
try FileManager.default.removeItem(at: iconset)
print(iconutil.terminationStatus == 0 ? "wrote \(output.path)/AppIcon.icns" : "iconutil failed")
