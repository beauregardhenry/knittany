import Foundation

/// Someone to knit for, with the measurements actually taken.
public struct Person: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    /// Measured values in cm. Anything missing can be estimated.
    public var measurements: [BodyMeasure: Double]
    public var units: UnitPreference
    public var notes: String

    public init(id: UUID = UUID(), name: String, measurements: [BodyMeasure: Double] = [:], units: UnitPreference = .cmFirst, notes: String = "") {
        self.id = id
        self.name = name
        self.measurements = measurements
        self.units = units
        self.notes = notes
    }

    /// The Craft Yarn Council value for a measurement that wasn't taken,
    /// based on the chest. Nil if it was taken, or can't be estimated.
    public func estimate(_ measure: BodyMeasure) -> Double? {
        guard measurements[measure] == nil, let chest = measurements[.chest] else { return nil }
        return StandardSizing.estimate(measure, chest: chest)
    }
}

/// One pattern regraded for one person.
public struct Project: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var patternID: UUID
    public var personID: UUID?
    public var options: [String: Double]
    /// The knitter's measured gauge; nil means the pattern's gauge.
    public var gauge: Gauge?
    public var easeOverrides: [GarmentMeasure: Double]
    public var finishedOverrides: [GarmentMeasure: Double]
    public var units: UnitPreference
    public var createdAt: Date
    public var notes: String

    public init(
        id: UUID = UUID(), name: String, patternID: UUID, personID: UUID? = nil,
        options: [String: Double] = [:], gauge: Gauge? = nil,
        easeOverrides: [GarmentMeasure: Double] = [:], finishedOverrides: [GarmentMeasure: Double] = [:],
        units: UnitPreference = .cmFirst, createdAt: Date = Date(), notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.patternID = patternID
        self.personID = personID
        self.options = options
        self.gauge = gauge
        self.easeOverrides = easeOverrides
        self.finishedOverrides = finishedOverrides
        self.units = units
        self.createdAt = createdAt
        self.notes = notes
    }

    /// Regrades the pattern for this project. Only measurements the person
    /// actually took are used; the rest follow the designer's grading.
    public func regrade(pattern: Pattern, person: Person?) throws -> (result: GradeResult, plan: FitPlan) {
        let plan = try EaseModel.plan(
            for: pattern,
            body: person?.measurements ?? [:],
            easeOverrides: easeOverrides,
            finishedOverrides: finishedOverrides,
            options: options
        )
        let result = try Grader(pattern: pattern).grade(
            GradeRequest(targets: plan.gradeTargets, gauge: gauge, options: options, units: units)
        )
        return (result, plan)
    }
}

public struct PatternEntry: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var designer: String?
    public var addedAt: Date
    public var hasSourcePDF: Bool
}

public struct LibraryIndex: Codable, Sendable, Equatable {
    public var people: [Person] = []
    public var patterns: [PatternEntry] = []
    public var projects: [Project] = []
    public init() {}
}

/// Everything the app keeps, as plain files in one folder:
/// `library.json`, plus `patterns/<id>/pattern.json` and `source.pdf`.
public struct LibraryStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Knitting", isDirectory: true)
    }

    var indexURL: URL { root.appendingPathComponent("library.json") }

    func folder(_ id: UUID) -> URL {
        root.appendingPathComponent("patterns", isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true)
    }

    public func patternURL(_ id: UUID) -> URL { folder(id).appendingPathComponent("pattern.json") }
    public func sourcePDFURL(_ id: UUID) -> URL { folder(id).appendingPathComponent("source.pdf") }

    public func load() throws -> LibraryIndex {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return LibraryIndex() }
        return try JSONDecoder().decode(LibraryIndex.self, from: Data(contentsOf: indexURL))
    }

    public func save(_ index: LibraryIndex) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(index).write(to: indexURL, options: .atomic)
    }

    /// Copies a pattern file (and optionally its original PDF) into the library.
    public func importPattern(from json: URL, sourcePDF: URL? = nil, into index: inout LibraryIndex) throws -> PatternEntry {
        let pattern = try Pattern.load(from: json)
        let id = UUID()
        let fm = FileManager.default
        try fm.createDirectory(at: folder(id), withIntermediateDirectories: true)
        try fm.copyItem(at: json, to: patternURL(id))
        if let pdf = sourcePDF {
            try fm.copyItem(at: pdf, to: sourcePDFURL(id))
        }
        let entry = PatternEntry(id: id, name: pattern.name, designer: pattern.designer, addedAt: Date(), hasSourcePDF: sourcePDF != nil)
        index.patterns.append(entry)
        try save(index)
        return entry
    }

    public func attachSourcePDF(_ pdf: URL, to id: UUID, in index: inout LibraryIndex) throws {
        let dest = sourcePDFURL(id)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: pdf, to: dest)
        if let i = index.patterns.firstIndex(where: { $0.id == id }) {
            index.patterns[i].hasSourcePDF = true
        }
        try save(index)
    }

    public func pattern(_ id: UUID) throws -> Pattern {
        try Pattern.load(from: patternURL(id))
    }

    /// Removes a pattern and its projects; its files go to the Trash.
    public func deletePattern(_ id: UUID, from index: inout LibraryIndex) throws {
        index.patterns.removeAll { $0.id == id }
        index.projects.removeAll { $0.patternID == id }
        if FileManager.default.fileExists(atPath: folder(id).path) {
            try FileManager.default.trashItem(at: folder(id), resultingItemURL: nil)
        }
        try save(index)
    }
}
