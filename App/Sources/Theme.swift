import SwiftUI

/// The colours of Malabrigo's Arco Iris, the yarn in the app icon
/// (App/Icon/make_icon.swift draws with the same values).
enum Yarn {
    static let yellow = Color(hex: 0xF5C518)
    static let orange = Color(hex: 0xF07C2A)
    static let red = Color(hex: 0xD7263D)
    static let pink = Color(hex: 0xE6397A)
    static let purple = Color(hex: 0x9B5FC0)
    static let green = Color(hex: 0x7CC242)
    static let leaf = Color(hex: 0x3FAE6A)
    /// The icon's background.
    static let aubergine = Color(hex: 0x2A1F3D)

    /// In the order the colours run through the skein.
    static let rainbow = [yellow, orange, red, pink, purple, green, leaf]

    /// A colour per item, so neighbours in a list differ.
    static func colour(_ index: Int) -> Color { rainbow[index % rainbow.count] }

    /// Dark text reads better than white on the light colours.
    static func ink(on colour: Color) -> Color {
        [yellow, orange, green, leaf].contains(colour) ? aubergine : .white
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// A row of knit stitches in the yarn's colours, like the icon's swatch.
struct StitchBand: View {
    var stitchWidth: CGFloat = 18
    var rows = 1

    var body: some View {
        Canvas { context, size in
            let w = stitchWidth, h = stitchWidth * 0.9
            let columns = Int((size.width / w).rounded(.up))
            for row in 0..<rows {
                for column in 0...columns {
                    let colour = Yarn.colour(column + row * 3)
                    let centre = CGPoint(x: CGFloat(column) * w + w / 2, y: CGFloat(row) * h * 0.8 + h / 2)
                    for side in [-1.0, 1.0] {
                        // One leg of the V: a leaf leaning in towards the stitch's foot.
                        let leg = Path(ellipseIn: CGRect(x: -w * 0.17, y: -h * 0.5, width: w * 0.34, height: h))
                        let transform = CGAffineTransform(translationX: centre.x + side * w * 0.2, y: centre.y)
                            .rotated(by: side * -0.55)
                        context.fill(leg.applying(transform), with: .color(colour))
                    }
                }
            }
        }
        .frame(height: stitchWidth * 0.9 * (1 + 0.8 * CGFloat(rows - 1)))
        .accessibilityHidden(true)
    }
}

/// A thin rainbow stripe across the top of each page.
struct RainbowStripe: View {
    var body: some View {
        LinearGradient(colors: Yarn.rainbow, startPoint: .leading, endPoint: .trailing)
            .frame(height: 4)
            .accessibilityHidden(true)
    }
}

/// A rounded, filled button in one of the yarn colours.
struct YarnButtonStyle: ButtonStyle {
    let colour: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.semibold)
            .foregroundStyle(Yarn.ink(on: colour))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(colour.opacity(configuration.isPressed ? 0.75 : 1), in: Capsule())
            .contentShape(Capsule())
    }
}

extension View {
    /// The rainbow stripe along the top of a page.
    func rainbowTop() -> some View {
        safeAreaInset(edge: .top, spacing: 0) { RainbowStripe() }
    }
}
