// Renders Resources/AppIcon.icns. Run: swift scripts/make-icon.swift
import AppKit

func render(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024
    let rect = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let path = NSBezierPath(roundedRect: rect, xRadius: 185 * s, yRadius: 185 * s)

    NSGraphicsContext.current?.cgContext.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 24 * s,
                                                   color: NSColor.black.withAlphaComponent(0.3).cgColor)
    NSGradient(colors: [NSColor(red: 0.36, green: 0.30, blue: 0.95, alpha: 1),
                        NSColor(red: 0.10, green: 0.62, blue: 0.98, alpha: 1)])!.draw(in: path, angle: -60)
    NSGraphicsContext.current?.cgContext.setShadow(offset: .zero, blur: 0, color: nil)

    // Soft top highlight
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
        .draw(in: path, angle: -90)

    func symbol(_ name: String, points: CGFloat, weight: NSFont.Weight, colors: [NSColor]) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: points * s, weight: weight)
            .applying(.init(paletteColors: colors))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    }

    let phone = symbol("iphone.gen3", points: 520, weight: .thin, colors: [.white, .white.withAlphaComponent(0.25)])
    phone.draw(in: NSRect(x: 512 * s - phone.size.width / 2 - 70 * s, y: 512 * s - phone.size.height / 2 + 40 * s,
                          width: phone.size.width, height: phone.size.height))

    let arrow = symbol("arrow.down.circle.fill", points: 230, weight: .bold, colors: [NSColor(red: 0.2, green: 0.45, blue: 0.97, alpha: 1), .white])
    let arrowRect = NSRect(x: 545 * s, y: 175 * s, width: arrow.size.width, height: arrow.size.height)
    NSGraphicsContext.current?.cgContext.setShadow(offset: CGSize(width: 0, height: -6 * s), blur: 16 * s,
                                                   color: NSColor.black.withAlphaComponent(0.25).cgColor)
    arrow.draw(in: arrowRect)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let iconset = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = CGFloat(base * scale)
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! render(size: px).representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
