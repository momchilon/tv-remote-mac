import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        NSColor(calibratedWhite: 0.055, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 210, yRadius: 210).fill()
        NSColor(calibratedWhite: 0.94, alpha: 1).setStroke()
        let remote = NSBezierPath(roundedRect: NSRect(x: 335, y: 170, width: 354, height: 684), xRadius: 150, yRadius: 150)
        remote.lineWidth = 32
        remote.stroke()
        let circle = NSBezierPath(ovalIn: NSRect(x: 405, y: 445, width: 214, height: 214))
        circle.lineWidth = 22
        circle.stroke()
        NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 488, y: 528, width: 48, height: 48)).fill()
        NSBezierPath(roundedRect: NSRect(x: 433, y: 309, width: 58, height: 26), xRadius: 13, yRadius: 13).fill()
        NSBezierPath(roundedRect: NSRect(x: 534, y: 309, width: 58, height: 26), xRadius: 13, yRadius: 13).fill()
        NSColor(calibratedRed: 0.34, green: 0.79, blue: 0.55, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 489, y: 738, width: 46, height: 46)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let filename = "icon_\(size)x\(size)\(suffix).png"
        try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(filename))
    }
}
