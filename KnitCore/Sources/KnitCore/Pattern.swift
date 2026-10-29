import Foundation

/// A pattern rebuilt as a parametric model: every number that changes between
/// sizes is a named quantity, and the instructions are templates that refer to
/// those quantities. Regrading computes new quantities; the text follows.
public struct Pattern: Codable, Sendable {
    public var name: String
    public var designer: String?
    public var source: String?
    public var construction: String?
    public var garment: GarmentType?
    public var sizes: [String]
    public var gauge: Gauge
    /// The measurement that picks the size (almost always chest).
    public var primaryDimension: GarmentMeasure
    /// Ease the designer recommends, in cm, e.g. `{"chest": 17.5}`.
    public var statedEase: [GarmentMeasure: Double]?
    public var options: [PatternOption]?
    public var schematic: [SchematicEntry]
    public var quantities: [Quantity]
    public var checks: [PatternCheck]?
    public var sections: [Section]
    public var charts: [Chart]?
    public var sourcePages: [SourcePage]?

    public static func load(from url: URL) throws -> Pattern {
        let pattern = try JSONDecoder().decode(Pattern.self, from: Data(contentsOf: url))
        try pattern.validate()
        return pattern
    }

    public func validate() throws {
        let n = sizes.count
        guard n > 0 else { throw PatternError("\(name): no sizes") }
        var seen = Set<String>()
        for q in quantities {
            guard seen.insert(q.id).inserted else { throw PatternError("duplicate quantity \(q.id)") }
            if let v = q.values, v.count != n {
                throw PatternError("\(q.id) has \(v.count) values for \(n) sizes")
            }
            if q.formula == nil && q.values == nil && q.value == nil {
                throw PatternError("\(q.id) needs values, a value or a formula")
            }
        }
        for s in schematic where s.values.count != n {
            throw PatternError("schematic \(s.id) has \(s.values.count) values for \(n) sizes")
        }
        guard schematic.contains(where: { $0.dimension == primaryDimension }) else {
            throw PatternError("the schematic has no \(primaryDimension.rawValue) measurement")
        }
        for chart in charts ?? [] {
            try chart.validate()
        }
    }

    public var defaultOptions: [String: Double] {
        Dictionary(uniqueKeysWithValues: (options ?? []).map { ($0.id, $0.defaultValue) })
    }

    /// The same pattern without one published size (for the designer test).
    public func removingSize(at index: Int) -> Pattern {
        var p = self
        p.sizes.remove(at: index)
        for i in p.quantities.indices {
            p.quantities[i].values?.remove(at: index)
        }
        for i in p.schematic.indices {
            p.schematic[i].values.remove(at: index)
        }
        return p
    }

    public init(
        name: String, designer: String? = nil, source: String? = nil, construction: String? = nil,
        garment: GarmentType? = nil, sizes: [String], gauge: Gauge, primaryDimension: GarmentMeasure = .chest,
        statedEase: [GarmentMeasure: Double]? = nil, options: [PatternOption]? = nil, schematic: [SchematicEntry],
        quantities: [Quantity], checks: [PatternCheck]? = nil, sections: [Section], charts: [Chart]? = nil,
        sourcePages: [SourcePage]? = nil
    ) {
        self.name = name
        self.designer = designer
        self.source = source
        self.construction = construction
        self.garment = garment
        self.sizes = sizes
        self.gauge = gauge
        self.primaryDimension = primaryDimension
        self.statedEase = statedEase
        self.options = options
        self.schematic = schematic
        self.quantities = quantities
        self.checks = checks
        self.sections = sections
        self.charts = charts
        self.sourcePages = sourcePages
    }
}

public enum GarmentType: String, Codable, Sendable {
    case pullover
    case cardigan
}

public struct PatternError: Error, CustomStringConvertible {
    public var description: String
    public init(_ description: String) { self.description = description }
}

public struct PatternOption: Codable, Sendable {
    public var id: String
    public var label: String
    public var defaultValue: Double

    enum CodingKeys: String, CodingKey {
        case id, label
        case defaultValue = "default"
    }
}

public struct SchematicEntry: Codable, Sendable {
    public var id: String
    public var label: String
    public var dimension: GarmentMeasure
    /// Designer's finished measurement per size, in cm.
    public var values: [Double]
    /// Only applies when this formula is true (e.g. one length per version).
    public var when: String?
    /// Formula for what the regraded stitch counts actually give, in cm.
    public var achieved: String?

    public init(id: String, label: String, dimension: GarmentMeasure, values: [Double], when: String? = nil, achieved: String? = nil) {
        self.id = id
        self.label = label
        self.dimension = dimension
        self.values = values
        self.when = when
        self.achieved = achieved
    }
}

public enum QuantityKind: String, Codable, Sendable {
    case stitches
    case rows
    case length
    case count
    case yarn
    case number

    var isWhole: Bool {
        switch self {
        case .stitches, .rows, .count: true
        case .length, .yarn, .number: false
        }
    }
}

public enum GradeMode: String, Codable, Sendable {
    /// Follow the designer's grading along the driver measurement.
    case scale
    /// Keep the designer's value and add the change in the driver measurement
    /// (for lengths like "work until the body measures 32.5 cm").
    case offset
}

/// What a count scales with when the knitter's gauge differs from the pattern's.
public enum ScaleBasis: String, Codable, Sendable {
    case stitches
    case rows
}

public struct Rounding: Codable, Sendable {
    public var multiple: Double
    public var remainder: Double?
}

public struct Quantity: Codable, Sendable {
    public var id: String
    public var kind: QuantityKind
    public var label: String?
    /// Designer's value per size. For a formula quantity these are only used
    /// to check the formula against the pattern.
    public var values: [Double]?
    /// The same value in every size.
    public var value: Double?
    public var driver: GarmentMeasure?
    public var mode: GradeMode?
    public var formula: String?
    public var round: Rounding?
    public var per: ScaleBasis?
    /// A working value the knitter never sees (left out of the designer test scores).
    public var `internal`: Bool?

    public func designerValue(size index: Int) -> Double? {
        values?[index] ?? value
    }

    public init(
        id: String, kind: QuantityKind, label: String? = nil, values: [Double]? = nil, value: Double? = nil,
        driver: GarmentMeasure? = nil, mode: GradeMode? = nil, formula: String? = nil, round: Rounding? = nil,
        per: ScaleBasis? = nil, internal: Bool? = nil
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.values = values
        self.value = value
        self.driver = driver
        self.mode = mode
        self.formula = formula
        self.round = round
        self.per = per
        self.internal = `internal`
    }
}

public struct PatternCheck: Codable, Sendable {
    /// Must be true; otherwise `message` is shown.
    public var expr: String
    public var message: String
    public var when: String?
}

public struct Section: Codable, Sendable {
    public var title: String
    public var when: String?
    /// Instruction lines. A line starting with "## " is a sub-heading.
    public var lines: [String]

    public init(title: String, when: String? = nil, lines: [String]) {
        self.title = title
        self.when = when
        self.lines = lines
    }
}
