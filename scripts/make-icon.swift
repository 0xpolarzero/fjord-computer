// swift scripts/make-icon.swift [--preview DIR] → Resources/AppIcon.icns and the layers of Resources/AppIcon.icon
//
// Fjord's mark, sun over water (docs/design/fjord/mark.html), on an ink tile: the classic icon, for every macOS. The same
// numbers draw the Icon Composer document's three layers (the sun, band 1, band 2), whose icon.json is written by hand.
// `--preview DIR` also writes the icon on ink and on paper at 1024 px.
import AppKit

// The construction, in the circle's diameters from its top: keep in step with `FjordMark` (Sources/Lookout/FjordMark.swift).
let split = 0.55, gap = 0.072, bands = [0.2, 0.11]
let spans: [(top: Double, bottom: Double)] = {
    var y = split, out = [(top: 0.0, bottom: split)]
    for b in bands { y += gap; out.append((y, min(1, y + b))); y += b }
    return out
}()

// The studio's colours (amont/brand, colors/tokens.json).
let ink = NSColor(srgbRed: 0x10 / 255, green: 0x14 / 255, blue: 0x18 / 255, alpha: 1)
let paper = NSColor(srgbRed: 0xF7 / 255, green: 0xF8 / 255, blue: 0xF5 / 255, alpha: 1)
let fonte = NSColor(srgbRed: 0x0F / 255, green: 0x9A / 255, blue: 0xC3 / 255, alpha: 1)

/// The mark's width in its tile, as mark.html sets it.
let markInTile = 0.6

/// The icon at `px`, on Apple's macOS grid: an 824 tile in 1024, corners 22.5% of it, a soft shadow in the margin.
func render(_ px: Int, dark: Bool = true) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 100 / 1024
    let tile = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bg = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -s * 10 / 1024)
    shadow.shadowBlurRadius = s * 20 / 1024
    shadow.set()
    (dark ? ink : paper).setFill(); bg.fill()
    NSGraphicsContext.restoreGraphicsState()
    // mark.html's hairline round the tile, so ink holds its edge on a dark Dock.
    bg.addClip()
    NSColor(srgbRed: 127 / 255, green: 140 / 255, blue: 150 / 255, alpha: 0.28).setStroke()
    bg.lineWidth = max(1, tile.width / 150) * 2; bg.stroke()

    let d = tile.width * markInTile
    let box = CGRect(x: tile.midX - d / 2, y: tile.midY - d / 2, width: d, height: d)
    let circle = CGPath(ellipseIn: box, transform: nil)
    let cg = NSGraphicsContext.current!.cgContext
    for (i, span) in spans.enumerated() {
        let strip = CGRect(x: box.minX, y: box.maxY - span.bottom * d, width: d, height: (span.bottom - span.top) * d)
        cg.addPath(circle.intersection(CGPath(rect: strip, transform: nil)))
        cg.setFillColor((i == 0 ? (dark ? paper : ink) : fonte).cgColor)
        cg.fillPath()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

/// One part as an SVG path on Icon Composer's 1024 canvas (y down), the circle `markInTile` of it, centred.
func svgPath(_ span: (top: Double, bottom: Double)) -> String {
    let d = 1024 * markInTile, r = d / 2, cx = 512.0, top = 512 - r
    func half(_ y: Double) -> Double { (max(0, r * r - (y - 512) * (y - 512))).squareRoot() }
    func f(_ v: Double) -> String { String(format: "%.3f", v) }
    let y0 = top + span.top * d, y1 = top + span.bottom * d
    let w0 = half(y0), w1 = half(y1)
    return "M\(f(cx - w0)) \(f(y0))H\(f(cx + w0))A\(f(r)) \(f(r)) 0 0 1 \(f(cx + w1)) \(f(y1))H\(f(cx - w1))A\(f(r)) \(f(r)) 0 0 1 \(f(cx - w0)) \(f(y0))Z"
}

let fm = FileManager.default
let dir = URL(fileURLWithPath: "build/AppIcon.iconset")
try? fm.removeItem(at: dir)
try! fm.createDirectory(at: dir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: dir.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: dir.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", dir.path, "-o", "Resources/AppIcon.icns"]
try! iconutil.run(); iconutil.waitUntilExit()
precondition(iconutil.terminationStatus == 0, "iconutil failed")

// The layers' fills are the document's (icon.json): black here, so an SVG reads as a shape.
let assets = URL(fileURLWithPath: "Resources/AppIcon.icon/Assets")
try! fm.createDirectory(at: assets, withIntermediateDirectories: true)
for (name, span) in zip(["sun", "band-1", "band-2"], spans) {
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024"><path d="\(svgPath(span))" fill="#000000"/></svg>

    """
    try! svg.write(to: assets.appendingPathComponent("\(name).svg"), atomically: true, encoding: .utf8)
}

if let i = CommandLine.arguments.firstIndex(of: "--preview"), i + 1 < CommandLine.arguments.count {
    let out = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    try! fm.createDirectory(at: out, withIntermediateDirectories: true)
    try! render(1024).write(to: out.appendingPathComponent("icns-dark-1024.png"))
    try! render(1024, dark: false).write(to: out.appendingPathComponent("icns-light-1024.png"))
    for px in [16, 32, 64] { try! render(px).write(to: out.appendingPathComponent("icns-dark-\(px).png")) }
}
