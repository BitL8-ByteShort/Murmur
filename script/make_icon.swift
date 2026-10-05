import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let p = CGFloat(pixels)
        NSColor(calibratedRed: 0.055, green: 0.066, blue: 0.075, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: p * 0.04, y: p * 0.04, width: p * 0.92, height: p * 0.92),
                     xRadius: p * 0.22, yRadius: p * 0.22).fill()
        let colors: [NSColor] = [.init(calibratedRed: 0.47, green: 0.94, blue: 0.79, alpha: 1),
                                .init(calibratedRed: 0.42, green: 0.69, blue: 1, alpha: 1),
                                .init(calibratedRed: 0.77, green: 0.64, blue: 1, alpha: 1)]
        for (index, height) in [0.15, 0.30, 0.49, 0.35, 0.20].enumerated() {
            colors[min(2, index / 2)].setFill()
            NSBezierPath(roundedRect: NSRect(x: p * (0.21 + Double(index) * 0.12), y: p * (0.5 - height / 2),
                                            width: p * 0.065, height: p * height), xRadius: p * 0.033, yRadius: p * 0.033).fill()
        }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(name))
    }
}
