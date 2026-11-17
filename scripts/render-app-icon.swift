import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = NSSize(width: 1024, height: 1024)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 200, yRadius: 200)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
        shadow.shadowBlurRadius = 24
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        shadow.set()
        NSColor(calibratedWhite: 0.16, alpha: 1).setFill()
        tile.fill()
        NSShadow().set()
        NSGradient(starting: NSColor(srgbRed: 0.22, green: 0.27, blue: 0.34, alpha: 1),
                   ending: NSColor(srgbRed: 0.12, green: 0.15, blue: 0.21, alpha: 1))!
            .draw(in: tile, angle: -90)
        let glyph = NSImage(systemSymbolName: "personalhotspot", accessibilityDescription: nil)!
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 480, weight: .regular))!
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.white]))!
        let factor = min(600 / glyph.size.width, 480 / glyph.size.height)
        let w = glyph.size.width * factor, h = glyph.size.height * factor
        glyph.draw(in: NSRect(x: (1024 - w) / 2, y: (1024 - h) / 2, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!
            .write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
