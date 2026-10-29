import Foundation
import KnitCore

/// What a reader found in a pattern PDF, for the knitter to check and correct
/// before it becomes a pattern. Both the offline reader and Claude produce this.
public struct ImportDraft: Codable, Sendable, Equatable {
    public enum Method: String, Codable, Sendable {
        case offline
        case claude
    }

    public var method: Method
    public var name: String
    public var designer: String
    /// "pullover", "cardigan" or nil when unknown.
    public var garment: GarmentType?
    public var sizes: [String]
    public var gauge: DraftGauge
    /// Ease the designer recommends at the chest, in cm.
    public var chestEase: Double?
    public var measurements: [DraftMeasurement]
    public var numbers: [DraftNumber]
    public var sections: [DraftSection]
    public var chartPages: [DraftPage]
    /// Things the knitter should check, e.g. steps written for one size only.
    public var notes: [String]

    public init(
        method: Method, name: String, designer: String, garment: GarmentType?, sizes: [String], gauge: DraftGauge,
        chestEase: Double?, measurements: [DraftMeasurement], numbers: [DraftNumber], sections: [DraftSection],
        chartPages: [DraftPage], notes: [String]
    ) {
        self.method = method
        self.name = name
        self.designer = designer
        self.garment = garment
        self.sizes = sizes
        self.gauge = gauge
        self.chestEase = chestEase
        self.measurements = measurements
        self.numbers = numbers
        self.sections = sections
        self.chartPages = chartPages
        self.notes = notes
    }

    /// Numbers that the included sections refer to.
    public var usedNumberIDs: Set<String> {
        var ids = Set<String>()
        for section in sections where section.include {
            for line in section.lines {
                for id in Self.placeholders(in: line) { ids.insert(id) }
            }
        }
        return ids
    }

    /// The ids in a line's `{id}` or `{id:format}` placeholders.
    public static func placeholders(in line: String) -> [String] {
        var ids: [String] = []
        var rest = Substring(line)
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            let tag = rest[rest.index(after: open)..<close]
            ids.append(String(tag.split(separator: ":").first ?? tag))
            rest = rest[rest.index(after: close)...]
        }
        return ids
    }
}

public struct DraftGauge: Codable, Sendable, Equatable {
    public var stitchesPer10cm: Double
    public var rowsPer10cm: Double
    public var stitchPattern: String
    public var needle: String

    public init(stitchesPer10cm: Double, rowsPer10cm: Double, stitchPattern: String = "", needle: String = "") {
        self.stitchesPer10cm = stitchesPer10cm
        self.rowsPer10cm = rowsPer10cm
        self.stitchPattern = stitchPattern
        self.needle = needle
    }
}

/// A finished measurement from the pattern's size table or schematic.
public struct DraftMeasurement: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var label: String
    /// Which garment measurement this is; nil if it isn't one the app regrades by.
    public var dimension: GarmentMeasure?
    /// Per size, in cm.
    public var values: [Double]

    public init(id: String, label: String, dimension: GarmentMeasure?, values: [Double]) {
        self.id = id
        self.label = label
        self.dimension = dimension
        self.values = values
    }
}

/// A number in the instructions that changes with size, such as a cast-on count.
public struct DraftNumber: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: QuantityKind
    /// The measurement it grows with; nil means the chest (or whatever picks the size).
    public var driver: GarmentMeasure?
    /// Per size: stitches, rows, times, cm for lengths or metres for yarn.
    public var values: [Double]
    /// The sentence it came from, so the knitter can see what it is.
    public var context: String

    public init(id: String, kind: QuantityKind, driver: GarmentMeasure?, values: [Double], context: String) {
        self.id = id
        self.kind = kind
        self.driver = driver
        self.values = values
        self.context = context
    }
}

public struct DraftSection: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    /// Instruction lines with `{id}` where a size-dependent number goes
    /// (`{id:len}` for a length, `{id:yarn}` for yarn). "## " starts a sub-heading.
    public var lines: [String]
    /// Whether it goes into the pattern (abbreviations and yarn notes usually don't).
    public var include: Bool

    public init(id: String, title: String, lines: [String], include: Bool) {
        self.id = id
        self.title = title
        self.lines = lines
        self.include = include
    }
}

/// A page of the PDF, usually a chart, to print with the regraded pattern.
public struct DraftPage: Codable, Sendable, Equatable {
    public var title: String
    public var page: Int

    public init(title: String, page: Int) {
        self.title = title
        self.page = page
    }
}

public enum DraftSummary {
    public static func text(_ d: ImportDraft) -> String {
        var out = ["\(d.name)\(d.designer.isEmpty ? "" : " by \(d.designer)") (read \(d.method == .claude ? "with Claude" : "offline"))"]
        out.append("Sizes: \(d.sizes.joined(separator: ", "))")
        out.append("Gauge: \(MeasureFormatter.trim(d.gauge.stitchesPer10cm)) sts × \(MeasureFormatter.trim(d.gauge.rowsPer10cm)) rows per 10 cm \(d.gauge.stitchPattern)")
        if let e = d.chestEase { out.append("Chest ease: \(MeasureFormatter.trim(e)) cm") }
        out.append("Measurements:")
        for m in d.measurements {
            out.append("  \(m.label) [\(m.dimension?.rawValue ?? "–")]: \(m.values.map(MeasureFormatter.trim).joined(separator: ", ")) cm")
        }
        let used = d.usedNumberIDs
        out.append("Numbers: \(d.numbers.count), \(d.numbers.filter { used.contains($0.id) }.count) used in the instructions")
        out.append("Sections: " + d.sections.map { "\($0.title)\($0.include ? "" : " (left out)") \($0.lines.count)" }.joined(separator: ", "))
        if !d.chartPages.isEmpty { out.append("Pages to include: " + d.chartPages.map { "\($0.title) p\($0.page)" }.joined(separator: ", ")) }
        for n in d.notes { out.append("Check: \(n)") }
        return out.joined(separator: "\n")
    }
}
