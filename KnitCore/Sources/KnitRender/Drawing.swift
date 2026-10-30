import AppKit
import CoreText
import KnitCore

/// Shared helpers. All drawing here assumes a y-down context (origin top left),
/// as in SwiftUI's Canvas; the PDF exporter flips its context to match.
enum Ink {
    static let line = CGColor(gray: 0.15, alpha: 1)
    static let faint = CGColor(gray: 0.55, alpha: 1)
    static let grid = CGColor(gray: 0.7, alpha: 1)
    static let fill = CGColor(gray: 0.96, alpha: 1)
    static let accent = CGColor(red: 0.62, green: 0.16, blue: 0.20, alpha: 1)

    /// Multiplies every text size while a large-print PDF is being drawn.
    @TaskLocal static var textScale: CGFloat = 1

    static func font(_ size: CGFloat, bold: Bool = false) -> NSFont {
        bold ? .boldSystemFont(ofSize: size * textScale) : .systemFont(ofSize: size * textScale)
    }

    static func color(hex: String?) -> CGColor? {
        guard var s = hex?.trimmingCharacters(in: .whitespaces), s.hasPrefix("#"), s.count == 7 else { return nil }
        s.removeFirst()
        guard let v = Int(s, radix: 16) else { return nil }
        return CGColor(
            red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: 1
        )
    }

    enum Anchor { case left, center, right }

    /// Draws one line of text with its baseline centred vertically on `point`.
    @discardableResult
    static func text(
        _ string: String, at point: CGPoint, in ctx: CGContext,
        size: CGFloat = 9, bold: Bool = false, color: CGColor = Ink.line, anchor: Anchor = .center
    ) -> CGRect {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font(size, bold: bold),
            .foregroundColor: NSColor(cgColor: color) ?? .black,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attrs))
        let bounds = CTLineGetBoundsWithOptions(line, [])
        let x: CGFloat = switch anchor {
        case .left: point.x
        case .center: point.x - bounds.width / 2
        case .right: point.x - bounds.width
        }
        let baseline = point.y + size * textScale * 0.35
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
        return CGRect(x: x, y: baseline - bounds.height, width: bounds.width, height: bounds.height)
    }
}
