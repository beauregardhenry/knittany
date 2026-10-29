import Foundation

/// Which unit is shown first. Both are always shown.
public enum UnitPreference: String, Codable, Sendable, CaseIterable {
    case cmFirst
    case inchFirst
}

public struct MeasureFormatter: Sendable {
    public var preference: UnitPreference

    public init(preference: UnitPreference = .cmFirst) {
        self.preference = preference
    }

    /// Lengths are stored in cm. Shown to the nearest 0.25 cm and 0.25 inch.
    public func length(_ cm: Double) -> String {
        let cmText = Self.trim(Self.round(cm, to: 0.25)) + " cm"
        let inchText = Self.trim(Self.round(cm / 2.54, to: 0.25)) + "″"
        switch preference {
        case .cmFirst: return "\(cmText) / \(inchText)"
        case .inchFirst: return "\(inchText) / \(cmText)"
        }
    }

    /// Yarn amounts are stored in metres.
    public func yarn(_ metres: Double) -> String {
        let m = "\(Int(metres.rounded())) m"
        let yd = "\(Int((metres / 0.9144).rounded())) yd"
        switch preference {
        case .cmFirst: return "\(m) / \(yd)"
        case .inchFirst: return "\(yd) / \(m)"
        }
    }

    public func gauge(_ g: Gauge) -> String {
        let sts = Self.trim(g.stitchesPer10cm)
        let rows = Self.trim(g.rowsPer10cm)
        let base = "\(sts) sts × \(rows) rows = \(length(10))"
        return g.stitchPattern.map { "\(base) in \($0)" } ?? base
    }

    static func round(_ value: Double, to step: Double) -> Double {
        (value / step).rounded() * step
    }

    public static func trim(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        var s = String(format: "%.2f", value)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    public static func ordinal(_ n: Int) -> String {
        let tens = (n / 10) % 10
        let suffix: String
        switch (tens == 1, n % 10) {
        case (false, 1): suffix = "st"
        case (false, 2): suffix = "nd"
        case (false, 3): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }
}

public enum LengthParser {
    /// Parses "38in", "38\"", "38″", "96.5cm" or a bare number (cm) into cm.
    public static func cm(from text: String) -> Double? {
        var s = text.trimmingCharacters(in: .whitespaces).lowercased()
        var factor = 1.0
        for (suffix, f) in [("inches", 2.54), ("inch", 2.54), ("in", 2.54), ("\"", 2.54), ("″", 2.54), ("cm", 1.0)] {
            if s.hasSuffix(suffix) {
                s.removeLast(suffix.count)
                factor = f
                break
            }
        }
        guard let v = Double(s.trimmingCharacters(in: .whitespaces)) else { return nil }
        return v * factor
    }
}
