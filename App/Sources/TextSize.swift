import SwiftUI

/// How big the app's text is, chosen in Settings or with ⌘+ and ⌘− (View menu).
/// macOS has no system-wide text size that reaches apps like this, so Knittany
/// scales its own text, and the exported PDF can be large print too.
enum TextSize: String, CaseIterable, Identifiable {
    case standard
    case large
    case extraLarge

    static let key = "textSize"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: "Standard"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        }
    }

    /// How much the exported PDF's text grows.
    var pdfScale: CGFloat {
        switch self {
        case .standard: 1
        case .large: 1.3
        case .extraLarge: 1.6
        }
    }

    var bigger: TextSize? {
        switch self {
        case .standard: .large
        case .large: .extraLarge
        case .extraLarge: nil
        }
    }

    var smaller: TextSize? {
        switch self {
        case .standard: nil
        case .large: .standard
        case .extraLarge: .large
        }
    }

    /// Point size for each style. The small grey notes grow the most, since
    /// they're the hardest to read at the standard size.
    func points(_ style: TextStyle) -> CGFloat {
        let sizes: (body: CGFloat, callout: CGFloat, caption: CGFloat, subheadline: CGFloat, headline: CGFloat, title: CGFloat, counter: CGFloat) =
            switch self {
            case .standard: (13, 12, 10, 11, 13, 22, 30)
            case .large: (16, 15, 13.5, 14, 17, 26, 40)
            case .extraLarge: (19, 18, 16.5, 17, 20, 30, 50)
            }
        return switch style {
        case .body: sizes.body
        case .callout: sizes.callout
        case .caption: sizes.caption
        case .subheadline: sizes.subheadline
        case .headline: sizes.headline
        case .title: sizes.title
        case .counter: sizes.counter
        }
    }
}

enum TextStyle {
    case body, callout, caption, subheadline, headline, title, counter
}

/// Sets a text style at the chosen size. Applied at the root of each window or
/// sheet for `.body`, so everything without its own style follows the setting.
struct ScaledFont: ViewModifier {
    @AppStorage(TextSize.key) private var size = TextSize.standard
    let style: TextStyle
    var bold = false
    var monospaced = false

    func body(content: Content) -> some View {
        let weight: Font.Weight = bold || style == .headline ? .semibold : (style == .counter ? .semibold : .regular)
        let design: Font.Design = monospaced ? .monospaced : (style == .counter ? .rounded : .default)
        return content.font(.system(size: size.points(style), weight: weight, design: design))
    }
}

/// The root of a window or sheet: body text at the chosen size, and larger
/// controls (buttons, pickers, switches) when the text is larger.
struct ScaledWindow: ViewModifier {
    @AppStorage(TextSize.key) private var size = TextSize.standard

    func body(content: Content) -> some View {
        content
            .modifier(ScaledFont(style: .body))
            .controlSize(size == .standard ? .regular : .large)
    }
}

extension View {
    func scaledFont(_ style: TextStyle, bold: Bool = false, monospaced: Bool = false) -> some View {
        modifier(ScaledFont(style: style, bold: bold, monospaced: monospaced))
    }

    func scaledWindow() -> some View {
        modifier(ScaledWindow())
    }
}

/// View > Bigger Text (⌘+), Smaller Text (⌘−) and Standard Text Size (⌘0).
struct TextSizeCommands: Commands {
    @AppStorage(TextSize.key) private var size = TextSize.standard

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Button("Bigger Text") { if let s = size.bigger { size = s } }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(size.bigger == nil)
            Button("Smaller Text") { if let s = size.smaller { size = s } }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(size.smaller == nil)
            Button("Standard Text Size") { size = .standard }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(size == .standard)
            Divider()
        }
    }
}
