import AppKit

// Draw the bundle icon locally using AppKit; packaging needs no downloaded assets.
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let colors: [NSColor] = [
    .systemBlue, .systemPurple, .systemPink,
    .systemTeal, .systemGreen, .systemOrange,
    .systemIndigo, .systemCyan, .systemYellow
]

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let plate = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 204, yRadius: 204)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowBlurRadius = 28
        shadow.shadowOffset = NSSize(width: 0, height: -12)
        shadow.set()
        NSColor(white: 0.9, alpha: 1).setFill()
        plate.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(starting: NSColor(white: 0.98, alpha: 1), ending: NSColor(white: 0.72, alpha: 1))!.draw(in: plate, angle: -90)
        NSColor.white.withAlphaComponent(0.65).setStroke()
        plate.lineWidth = 3
        plate.stroke()
        for row in 0..<3 {
            for column in 0..<3 {
                let color = colors[row * 3 + column]
                let rect = NSRect(x: 203 + column * 222, y: 647 - row * 222, width: 174, height: 174)
                let tile = NSBezierPath(roundedRect: rect, xRadius: 42, yRadius: 42)
                let top = color.blended(withFraction: 0.17, of: .white)!
                let bottom = color.blended(withFraction: 0.10, of: .black)!
                NSGradient(starting: top, ending: bottom)!.draw(in: tile, angle: -90)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let url = directory.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
}
