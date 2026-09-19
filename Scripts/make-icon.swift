import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/AppIcon.iconset")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let p = CGFloat(px)
        let rect = NSRect(x: p * 0.08, y: p * 0.08, width: p * 0.84, height: p * 0.84)
        let path = NSBezierPath(roundedRect: rect, xRadius: p * 0.21, yRadius: p * 0.21)
        NSGradient(starting: NSColor(red: 0.08, green: 0.36, blue: 0.28, alpha: 1), ending: NSColor(red: 0.18, green: 0.64, blue: 0.48, alpha: 1))!.draw(in: path, angle: 60)
        NSColor.white.withAlphaComponent(0.20).setStroke()
        let ring = NSBezierPath(ovalIn: NSRect(x: p * 0.2, y: p * 0.2, width: p * 0.6, height: p * 0.6)); ring.lineWidth = p * 0.025; ring.stroke()
        let bolt = NSBezierPath()
        bolt.move(to: NSPoint(x: p * 0.56, y: p * 0.78))
        bolt.line(to: NSPoint(x: p * 0.32, y: p * 0.46))
        bolt.line(to: NSPoint(x: p * 0.48, y: p * 0.46))
        bolt.line(to: NSPoint(x: p * 0.43, y: p * 0.23))
        bolt.line(to: NSPoint(x: p * 0.70, y: p * 0.56))
        bolt.line(to: NSPoint(x: p * 0.53, y: p * 0.56)); bolt.close()
        NSColor.white.setFill(); bolt.fill()
        NSGraphicsContext.restoreGraphicsState()
        let data = rep.representation(using: .png, properties: [:])!
        try data.write(to: root.appendingPathComponent("icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
    }
}
