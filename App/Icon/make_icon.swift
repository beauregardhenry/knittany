// Draws the app icon: a swatch of stockinette whose columns widen left to
// right, in the colours of Malabrigo's Arco Iris, on aubergine.
//
//   swift App/Icon/make_icon.swift App/Sources/Assets.xcassets/AppIcon.appiconset
//
// Writes every size macOS needs plus Contents.json.

import AppKit

func colour(_ hex: UInt32) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: 1
    )
}

let yellow: UInt32 = 0xF5C518, orange: UInt32 = 0xF07C2A, red: UInt32 = 0xD7263D
let pink: UInt32 = 0xE6397A, purple: UInt32 = 0x9B5FC0, green: UInt32 = 0x7CC242, leaf: UInt32 = 0x3FAE6A

/// Columns from narrow to wide, in the 1024 canvas: centre x, how far the legs
/// lean, how plump they are, and each stitch's (left leg, right leg) colours.
let columns: [(x: Double, lean: Double, plump: Double, stitches: [(UInt32, UInt32)])] = [
    (290, 22, 0.95, [(yellow, orange), (orange, red), (red, pink)]),
    (460, 32, 1.3, [(orange, red), (pink, purple), (purple, green)]),
    (681, 42, 1.7, [(pink, green), (green, leaf), (leaf, yellow)]),
]
/// Row centres; close enough that each V nests into the one above, as in stockinette.
let rows: [Double] = [372, 512, 652]
let legLength = 86.0

/// At 16 and 32 pixels nine stitches turn to mush, so the smallest icons use
/// four bigger ones that still widen to the right.
let smallColumns: [(x: Double, lean: Double, plump: Double, stitches: [(UInt32, UInt32)])] = [
    (353, 24, 1.1, [(yellow, orange), (red, pink)]),
    (607, 40, 1.7, [(pink, green), (leaf, yellow)]),
]
let smallRows: [Double] = [425, 600]
let smallLegLength = 110.0

/// One leg of a knit stitch: a leaf shape, point up and point down, in unit size.
func legPath() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0, y: -1))
    p.addCurve(to: CGPoint(x: 0, y: 1), control1: CGPoint(x: 0.62, y: -0.55), control2: CGPoint(x: 0.62, y: 0.55))
    p.addCurve(to: CGPoint(x: 0, y: -1), control1: CGPoint(x: -0.62, y: 0.55), control2: CGPoint(x: -0.62, y: -0.55))
    p.closeSubpath()
    return p
}

func draw(size: Int) -> Data {
    let px = CGFloat(size)
    let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    // Work in a 1024 canvas with y down, like the design sketches.
    ctx.scaleBy(x: px / 1024, y: px / 1024)
    ctx.translateBy(x: 0, y: 1024)
    ctx.scaleBy(x: 1, y: -1)

    // The macOS icon shape: an 824 pt rounded square with a soft shadow.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: CGColor(gray: 0, alpha: 0.28))
    ctx.addPath(shape)
    ctx.setFillColor(colour(0x2A1F3D))
    ctx.fillPath()
    ctx.restoreGState()

    // A gentle lift at the top so the tile doesn't look flat.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let lift = CGGradient(
        colorsSpace: nil,
        colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 0.07), CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(lift, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 600), options: [])
    ctx.restoreGState()

    // The swatch. Each leg leans out from the stitch's centre so the two
    // points meet at the bottom of the V.
    let leg = legPath()
    let small = size <= 32
    for column in small ? smallColumns : columns {
        let theta = column.lean * .pi / 180
        let h = small ? smallLegLength : legLength, w = 0.42 * h * column.plump, d = h * sin(theta)
        for (row, legs) in zip(small ? smallRows : rows, column.stitches) {
            for (side, hex) in [(-1.0, legs.0), (1.0, legs.1)] {
                ctx.saveGState()
                ctx.translateBy(x: column.x + side * d, y: row)
                ctx.rotate(by: side * theta)
                ctx.scaleBy(x: w, y: h)
                ctx.addPath(leg)
                ctx.setFillColor(colour(hex))
                ctx.fillPath()
                // A soft highlight down the leg, like the twist of the yarn.
                ctx.translateBy(x: -0.14, y: -0.1)
                ctx.scaleBy(x: 0.38, y: 0.68)
                ctx.addPath(leg)
                ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
                ctx.fillPath()
                ctx.restoreGState()
            }
        }
    }

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.appiconset")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try draw(size: points * scale).write(to: out.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: out.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icons to \(out.path)")
