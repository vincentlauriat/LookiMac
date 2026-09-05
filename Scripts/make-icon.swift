import AppKit
// Usage: swift Scripts/make-icon.swift LookiMac/Assets.xcassets/AppIcon.appiconset
import CoreGraphics

// Renders the Looki pour Mac app icon at a given pixel size following the macOS
// icon grid: the rounded square occupies 824/1024 of the canvas, corner radius 185/1024.
func render(size: Int, to url: URL) throws {
    let s = CGFloat(size)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    let u = s / 1024.0                                   // 1 unit of the 1024 grid

    // Drop shadow below the tile, as macOS does for its own icons.
    let tile = CGRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u)
    let path = CGPath(roundedRect: tile, cornerWidth: 185 * u, cornerHeight: 185 * u, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12 * u), blur: 28 * u, color: CGColor(red: 0.3, green: 0.05, blue: 0.1, alpha: 0.35))
    ctx.addPath(path); ctx.setFillColor(CGColor(red: 1, green: 0.45, blue: 0.52, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()

    // Diagonal gradient: #ff9fb0 -> #fb7185 -> #d1405a
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    let colors = [CGColor(red: 1.0, green: 0.62, blue: 0.69, alpha: 1),
                  CGColor(red: 0.984, green: 0.443, blue: 0.522, alpha: 1),
                  CGColor(red: 0.82, green: 0.25, blue: 0.35, alpha: 1)] as CFArray
    let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
    // Soft top highlight
    let hl = CGGradient(colorsSpace: cs, colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 0.22), CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(hl, start: CGPoint(x: tile.midX, y: tile.maxY), end: CGPoint(x: tile.midX, y: tile.midY), options: [])
    ctx.restoreGState()

    // Camera glyph (white strokes), centred. Coordinates on the 1024 grid, y up.
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.setLineWidth(58 * u)
    // body
    let body = CGRect(x: 232 * u, y: 300 * u, width: 560 * u, height: 380 * u)
    ctx.addPath(CGPath(roundedRect: body, cornerWidth: 80 * u, cornerHeight: 80 * u, transform: nil)); ctx.strokePath()
    // top bump (viewfinder)
    ctx.move(to: CGPoint(x: 392 * u, y: 680 * u)); ctx.addLine(to: CGPoint(x: 446 * u, y: 764 * u))
    ctx.addLine(to: CGPoint(x: 578 * u, y: 764 * u)); ctx.addLine(to: CGPoint(x: 632 * u, y: 680 * u)); ctx.strokePath()
    // lens
    ctx.setLineWidth(52 * u)
    ctx.addEllipse(in: CGRect(x: 512 * u - 112 * u, y: 490 * u - 112 * u, width: 224 * u, height: 224 * u)); ctx.strokePath()
    // lens glint + memory dot (the calendar mark), filled
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: 512 * u - 34 * u, y: 490 * u - 34 * u, width: 68 * u, height: 68 * u))
    ctx.fillEllipse(in: CGRect(x: 700 * u - 26 * u, y: 600 * u - 26 * u, width: 52 * u, height: 52 * u))

    let img = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: img)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
for size in [16, 32, 64, 128, 256, 512, 1024] {
    try render(size: size, to: out.appendingPathComponent("icon_\(size).png"))
    print("icon_\(size).png")
}
