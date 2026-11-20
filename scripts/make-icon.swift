#!/usr/bin/env swift
// Renders the Caffe Island app icon (1024×1024 PNG) with pure
// CoreGraphics — no SF Symbols (their licence forbids use in app icons), no
// text. Concept: a wide-awake, over-caffeinated mug on a tiny island at
// night, with the Dynamic Island pill floating at the top.
//
//   swift scripts/make-icon.swift App/Assets.xcassets/AppIcon.appiconset
//
// Writes icon_1024.png plus every size macOS needs, and Contents.json.
//
//   swift scripts/make-icon.swift --menubar App/Assets.xcassets
//
// Writes the menu bar glyphs (18×18 pt template images, 1× and 2×): the
// googly-eyed mug, idle (outline), active (filled + steam) and error (badge).
import AppKit
import CoreGraphics

let outDir = CommandLine.arguments.dropFirst().first ?? "AppIcon.appiconset"
let S: CGFloat = 1024

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func render() -> CGImage {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Top-left origin, y down — easier to reason about.
    ctx.translateBy(x: 0, y: S)
    ctx.scaleBy(x: 1, y: -1)

    // macOS icon grid: 824 pt rounded square centred on a 1024 canvas.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Drop shadow under the tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(tilePath); ctx.setFillColor(color(0x1B1F4B)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()

    // Night sky.
    let sky = CGGradient(colorsSpace: cs, colors: [color(0x141838), color(0x2E2A6B), color(0x5B3F8C)] as CFArray, locations: [0, 0.6, 1])!
    ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 720), options: [.drawsAfterEndLocation])

    // Stars.
    let stars: [(CGFloat, CGFloat, CGFloat)] = [(190, 260, 6), (260, 380, 4), (300, 220, 5), (700, 400, 4), (850, 330, 6),
                                                (620, 250, 3), (210, 520, 4), (880, 520, 4), (400, 300, 3)]
    ctx.setFillColor(color(0xFFF4D6, 0.9))
    for (x, y, r) in stars { ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)) }

    // Crescent moon (circle minus offset circle).
    ctx.saveGState()
    let moon = CGRect(x: 730, y: 190, width: 120, height: 120)
    let bite = CGMutablePath()
    bite.addRect(tile)
    bite.addEllipse(in: moon.offsetBy(dx: 34, dy: -22))
    ctx.addPath(bite); ctx.clip(using: .evenOdd)
    ctx.setFillColor(color(0xFFE7A8)); ctx.fillEllipse(in: moon)
    ctx.restoreGState()

    // The Dynamic Island pill.
    let pill = CGPath(roundedRect: CGRect(x: 402, y: 138, width: 220, height: 58), cornerWidth: 29, cornerHeight: 29, transform: nil)
    ctx.addPath(pill); ctx.setFillColor(color(0x000000)); ctx.fillPath()
    ctx.setFillColor(color(0x2BD67B)); ctx.fillEllipse(in: CGRect(x: 580, y: 159, width: 16, height: 16))

    // Sea + wave crest.
    let sea = CGGradient(colorsSpace: cs, colors: [color(0x29C4BA), color(0x0B6E86)] as CFArray, locations: [0, 1])!
    let seaPath = CGMutablePath()
    seaPath.move(to: CGPoint(x: 100, y: 760))
    for i in 0...8 {
        let x = 100 + CGFloat(i) * 103
        seaPath.addQuadCurve(to: CGPoint(x: x + 103, y: 760), control: CGPoint(x: x + 51, y: i % 2 == 0 ? 735 : 785))
    }
    seaPath.addLine(to: CGPoint(x: 924, y: 924)); seaPath.addLine(to: CGPoint(x: 100, y: 924)); seaPath.closeSubpath()
    ctx.saveGState(); ctx.addPath(seaPath); ctx.clip()
    ctx.drawLinearGradient(sea, start: CGPoint(x: 0, y: 730), end: CGPoint(x: 0, y: 924), options: [])
    ctx.restoreGState()

    // Sand island.
    ctx.setFillColor(color(0xE7B867)); ctx.fillEllipse(in: CGRect(x: 250, y: 712, width: 524, height: 120))
    ctx.setFillColor(color(0xF6D892)); ctx.fillEllipse(in: CGRect(x: 262, y: 702, width: 500, height: 100))

    let ink = color(0x3A2416)

    // Steam — three wavy wisps.
    ctx.setStrokeColor(color(0xFFFFFF, 0.85)); ctx.setLineWidth(18); ctx.setLineCap(.round)
    for (i, x) in [CGFloat(432), 492, 552].enumerated() {
        let top: CGFloat = i == 1 ? 290 : 330
        let p = CGMutablePath()
        p.move(to: CGPoint(x: x, y: 440))
        p.addCurve(to: CGPoint(x: x, y: top), control1: CGPoint(x: x - 34, y: 400), control2: CGPoint(x: x + 34, y: top + 40))
        ctx.addPath(p); ctx.strokePath()
    }

    // Mug handle (behind body).
    ctx.setLineWidth(46); ctx.setStrokeColor(ink)
    ctx.strokeEllipse(in: CGRect(x: 560, y: 520, width: 150, height: 150))
    ctx.setLineWidth(24); ctx.setStrokeColor(color(0xFFF6EA))
    ctx.strokeEllipse(in: CGRect(x: 560, y: 520, width: 150, height: 150))

    // Mug body.
    let body = CGMutablePath()
    body.move(to: CGPoint(x: 342, y: 470))
    body.addLine(to: CGPoint(x: 642, y: 470))
    body.addLine(to: CGPoint(x: 628, y: 680))
    body.addQuadCurve(to: CGPoint(x: 568, y: 742), control: CGPoint(x: 624, y: 742))
    body.addLine(to: CGPoint(x: 416, y: 742))
    body.addQuadCurve(to: CGPoint(x: 356, y: 680), control: CGPoint(x: 360, y: 742))
    body.closeSubpath()
    ctx.addPath(body); ctx.setFillColor(color(0xFFF6EA)); ctx.fillPath()
    ctx.addPath(body); ctx.setStrokeColor(ink); ctx.setLineWidth(14); ctx.setLineJoin(.round); ctx.strokePath()

    // Coffee surface.
    ctx.setFillColor(color(0x6B3E21)); ctx.fillEllipse(in: CGRect(x: 352, y: 452, width: 280, height: 40))
    ctx.setStrokeColor(ink); ctx.setLineWidth(12); ctx.strokeEllipse(in: CGRect(x: 342, y: 448, width: 300, height: 46))
    ctx.setFillColor(color(0xC98A55, 0.8)); ctx.fillEllipse(in: CGRect(x: 420, y: 462, width: 90, height: 14))

    // Googly, over-caffeinated eyes — pupils looking in different directions.
    let eyes: [(CGPoint, CGPoint)] = [(CGPoint(x: 435, y: 568), CGPoint(x: 452, y: 552)),
                                      (CGPoint(x: 552, y: 568), CGPoint(x: 540, y: 586))]
    for (c, pupil) in eyes {
        ctx.setFillColor(color(0xFFFFFF)); ctx.fillEllipse(in: CGRect(x: c.x - 54, y: c.y - 54, width: 108, height: 108))
        ctx.setStrokeColor(ink); ctx.setLineWidth(9); ctx.strokeEllipse(in: CGRect(x: c.x - 54, y: c.y - 54, width: 108, height: 108))
        ctx.setFillColor(color(0x111111)); ctx.fillEllipse(in: CGRect(x: pupil.x - 20, y: pupil.y - 20, width: 40, height: 40))
        ctx.setFillColor(color(0xFFFFFF)); ctx.fillEllipse(in: CGRect(x: pupil.x - 10, y: pupil.y - 12, width: 10, height: 10))
    }

    // Big jittery grin with teeth.
    let grin = CGMutablePath()
    grin.move(to: CGPoint(x: 432, y: 650))
    grin.addQuadCurve(to: CGPoint(x: 556, y: 650), control: CGPoint(x: 494, y: 735))
    grin.closeSubpath()
    ctx.addPath(grin); ctx.setFillColor(ink); ctx.fillPath()
    ctx.saveGState(); ctx.addPath(grin); ctx.clip()
    ctx.setFillColor(color(0xFFFFFF)); ctx.fill(CGRect(x: 430, y: 650, width: 130, height: 16))
    ctx.restoreGState()

    // Cheeks.
    ctx.setFillColor(color(0xFF8A8A, 0.55))
    ctx.fillEllipse(in: CGRect(x: 372, y: 640, width: 44, height: 24))
    ctx.fillEllipse(in: CGRect(x: 572, y: 640, width: 44, height: 24))

    // Jitter lines either side.
    ctx.setStrokeColor(color(0xFFE7A8)); ctx.setLineWidth(12); ctx.setLineCap(.round)
    for (a, b) in [((300, 540), (268, 528)), ((296, 600), (258, 600)), ((300, 660), (268, 672)),
                   ((738, 520), (772, 506)), ((744, 600), (782, 600))] {
        ctx.move(to: CGPoint(x: a.0, y: a.1)); ctx.addLine(to: CGPoint(x: b.0, y: b.1))
    }
    ctx.strokePath()

    // Subtle top highlight.
    let gloss = CGGradient(colorsSpace: cs, colors: [color(0xFFFFFF, 0.10), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gloss, start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 420), options: [])
    ctx.restoreGState()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, size: Int, to path: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    g.imageInterpolation = .high
    NSGraphicsContext.current = g
    g.cgContext.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

// MARK: - Menu bar glyphs

enum GlyphState: String, CaseIterable { case idle = "MenuBarMug", active = "MenuBarMugActive", error = "MenuBarMugError" }

/// Draws one 18×18 pt glyph, black on transparent (template: only alpha
/// matters, macOS tints it for light/dark/highlighted menu bars).
func renderGlyph(_ state: GlyphState, scale: CGFloat) -> CGImage {
    let px = Int(18 * scale)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: scale, y: scale)
    ctx.translateBy(x: 0, y: 18); ctx.scaleBy(x: 1, y: -1)     // top-left origin, points
    ctx.setShouldAntialias(true)
    let ink = CGColor(gray: 0, alpha: 1)
    ctx.setStrokeColor(ink); ctx.setFillColor(ink)
    ctx.setLineCap(.round); ctx.setLineJoin(.round)

    // Mug body: flat rim, rounded bottom. Steam leaves room above it.
    let body = CGMutablePath()
    body.move(to: CGPoint(x: 2.75, y: 6.25))
    body.addLine(to: CGPoint(x: 12.75, y: 6.25))
    body.addLine(to: CGPoint(x: 12.75, y: 12.5))
    body.addQuadCurve(to: CGPoint(x: 9.75, y: 15.5), control: CGPoint(x: 12.75, y: 15.5))
    body.addLine(to: CGPoint(x: 5.75, y: 15.5))
    body.addQuadCurve(to: CGPoint(x: 2.75, y: 12.5), control: CGPoint(x: 2.75, y: 15.5))
    body.closeSubpath()
    // Handle: a "D" on the right.
    let handle = CGMutablePath()
    handle.move(to: CGPoint(x: 12.75, y: 8.0))
    handle.addCurve(to: CGPoint(x: 12.75, y: 12.75), control1: CGPoint(x: 16.6, y: 7.6), control2: CGPoint(x: 16.6, y: 13.2))
    let eyes = [CGRect(x: 4.6, y: 8.5, width: 2.4, height: 2.4), CGRect(x: 8.4, y: 8.5, width: 2.4, height: 2.4)]

    ctx.setLineWidth(1.5)
    ctx.addPath(handle); ctx.strokePath()
    switch state {
    case .active:
        ctx.addPath(body); ctx.drawPath(using: .fillStroke)          // stroke keeps edges pixel-aligned
        ctx.setBlendMode(.clear)                                   // knock the eyes out
        for e in eyes { ctx.fillEllipse(in: e) }
        ctx.setBlendMode(.normal)
        ctx.setLineWidth(1.2)
        for x in [5.0, 7.75, 10.5] as [CGFloat] {                  // three wisps of steam
            ctx.move(to: CGPoint(x: x, y: 4.4))
            ctx.addCurve(to: CGPoint(x: x, y: 0.9), control1: CGPoint(x: x - 1.1, y: 3.3), control2: CGPoint(x: x + 1.1, y: 2.0))
        }
        ctx.strokePath()
    case .idle, .error:
        ctx.addPath(body); ctx.strokePath()
        for e in eyes { ctx.fillEllipse(in: e) }
    }
    if state == .error {
        // Badge bottom-right: clear a ring, then a solid dot with a "!" cut out.
        let c = CGPoint(x: 14.0, y: 14.0)
        ctx.setBlendMode(.clear)
        ctx.fillEllipse(in: CGRect(x: c.x - 4.6, y: c.y - 4.6, width: 9.2, height: 9.2))
        ctx.setBlendMode(.normal)
        ctx.fillEllipse(in: CGRect(x: c.x - 3.6, y: c.y - 3.6, width: 7.2, height: 7.2))
        ctx.setBlendMode(.clear)
        ctx.setLineWidth(1.3)
        ctx.move(to: CGPoint(x: c.x, y: c.y - 2.0)); ctx.addLine(to: CGPoint(x: c.x, y: c.y + 0.4)); ctx.strokePath()
        ctx.fillEllipse(in: CGRect(x: c.x - 0.7, y: c.y + 1.3, width: 1.4, height: 1.4))
        ctx.setBlendMode(.normal)
    }
    return ctx.makeImage()!
}

func writeMenuBarGlyphs(into catalog: String) {
    for state in GlyphState.allCases {
        let dir = "\(catalog)/\(state.rawValue).imageset"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        var images: [String] = []
        for scale in [1, 2] {
            let name = "\(state.rawValue)\(scale == 2 ? "@2x" : "").png"
            let rep = NSBitmapImageRep(cgImage: renderGlyph(state, scale: CGFloat(scale)))
            try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/\(name)"))
            images.append(#"{"idiom":"universal","scale":"\#(scale)x","filename":"\#(name)"}"#)
        }
        let json = #"{"images":[\#(images.joined(separator: ","))],"info":{"version":1,"author":"xcode"},"properties":{"template-rendering-intent":"template"}}"#
        try! json.write(toFile: "\(dir)/Contents.json", atomically: true, encoding: .utf8)
    }
    print("wrote menu bar glyphs to \(catalog)")
}

if CommandLine.arguments.dropFirst().first == "--menubar" {
    writeMenuBarGlyphs(into: CommandLine.arguments.dropFirst(2).first ?? "App/Assets.xcassets")
    exit(0)
}

try! FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let image = render()
var entries: [String] = []
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        writePNG(image, size: px, to: "\(outDir)/\(name)")
        entries.append(#"{"idiom":"mac","size":"\#(base)x\#(base)","scale":"\#(scale)x","filename":"\#(name)"}"#)
    }
}
writePNG(image, size: 1024, to: "\(outDir)/icon_1024.png")
let json = #"{"images":[\#(entries.joined(separator: ","))],"info":{"version":1,"author":"xcode"}}"#
try! json.write(toFile: "\(outDir)/Contents.json", atomically: true, encoding: .utf8)
print("wrote \(outDir)")
