import Foundation

/// Someone to knit for, with the measurements actually taken.
public struct Person: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    /// Measured values in cm. Anything missing can be estimated.
    public var measurements: [BodyMeasure: Double]
    public var units: UnitPreference
    public var notes: String
    /// Which standard chart estimates their missing measurements; nil means women's.
    public var chart: SizeChart?

    public init(
        id: UUID = UUID(), name: String, measurements: [BodyMeasure: Double] = [:], units: UnitPreference = .cmFirst,
        notes: String = "", chart: SizeChart? = nil
    ) {
        self.id = id
        self.name = name
        self.measurements = measurements
        self.units = units
        self.notes = notes
        self.chart = chart
    }

    public var sizeChart: SizeChart { chart ?? .women }

    /// The Craft Yarn Council value for a measurement that wasn't taken,
    /// based on the chest. Nil if it was taken, or can't be estimated.
    public func estimate(_ measure: BodyMeasure) -> Double? {
        guard measurements[measure] == nil, let chest = measurements[.chest] else { return nil }
        return sizeChart.estimate(measure, chest: chest)
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
    /// Where the knitter is: ticked-off steps and the row counter.
    public var progress: KnittingProgress?

    public init(
        id: UUID = UUID(), name: String, patternID: UUID, personID: UUID? = nil,
        options: [String: Double] = [:], gauge: Gauge? = nil,
        easeOverrides: [GarmentMeasure: Double] = [:], finishedOverrides: [GarmentMeasure: Double] = [:],
        units: UnitPreference = .cmFirst, createdAt: Date = Date(), notes: String = "",
        progress: KnittingProgress? = nil
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
        self.progress = progress
    }

    /// Regrades the pattern for this project. Only measurements the person
    /// actually took are used; the rest follow the designer's grading.
    public func regrade(pattern: Pattern, person: Person?) throws -> (result: GradeResult, plan: FitPlan) {
        let plan = try EaseModel.plan(
            for: pattern,
            body: person?.measurements ?? [:],
            easeOverrides: easeOverrides,
            finishedOverrides: finishedOverrides,
            options: options,
            chart: pattern.sizedFor ?? .women
        )
        let result = try Grader(pattern: pattern).grade(
            GradeRequest(targets: plan.gradeTargets, gauge: gauge, options: options, units: units)
        )
        return (result, plan)
    }
}

/// Progress through a regraded pattern while knitting it.
public struct KnittingProgress: Codable, Sendable, Equatable {
    /// Steps ticked off, as "section title|line number" (0-based).
    public var done: Set<String> = []
    public var counter: Int = 0

    public init(done: Set<String> = [], counter: Int = 0) {
        self.done = done
        self.counter = counter
    }

    public static func key(section: String, line: Int) -> String { "\(section)|\(line)" }
}

public struct PatternEntry: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var designer: String?
    public var addedAt: Date
    public var hasSourcePDF: Bool
    /// The knitter's own notes on the pattern.
    public var notes: String
    /// Starred, so it's listed under Favorites at the top of the sidebar.
    public var favorite: Bool

    public init(id: UUID, name: String, designer: String?, addedAt: Date, hasSourcePDF: Bool, notes: String = "", favorite: Bool = false) {
        self.id = id
        self.name = name
        self.designer = designer
        self.addedAt = addedAt
        self.hasSourcePDF = hasSourcePDF
        self.notes = notes
        self.favorite = favorite
    }

    enum CodingKeys: String, CodingKey {
        case id, name, designer, addedAt, hasSourcePDF, notes, favorite
    }

    /// Libraries saved before notes and favorites read as having none.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        designer = try c.decodeIfPresent(String.self, forKey: .designer)
        addedAt = try c.decode(Date.self, forKey: .addedAt)
        hasSourcePDF = try c.decode(Bool.self, forKey: .hasSourcePDF)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        favorite = try c.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
    }
}

public struct LibraryIndex: Codable, Sendable, Equatable {
    public var people: [Person] = []
    public var patterns: [PatternEntry] = []
    public var projects: [Project] = []
    public init() {}
}

/// Everything the app keeps, as plain files in one folder:
/// `library.json`, plus `patterns/<id>/pattern.json`, `source.pdf` and `photos/`.
public struct LibraryStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `~/Library/Application Support/Knittany`. A library from before the app
    /// was renamed (in a `Knitting` folder) is moved here the first time.
    public static var defaultRoot: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let root = support.appendingPathComponent("Knittany", isDirectory: true)
        moveLibrary(from: support.appendingPathComponent("Knitting", isDirectory: true), to: root)
        return root
    }

    /// Moves an old library folder to a new one, if there's an old one and no new one yet.
    static func moveLibrary(from old: URL, to new: URL) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: new.path), fm.fileExists(atPath: old.appendingPathComponent("library.json").path) else { return }
        try? fm.moveItem(at: old, to: new)
    }

    var indexURL: URL { root.appendingPathComponent("library.json") }

    func folder(_ id: UUID) -> URL {
        root.appendingPathComponent("patterns", isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true)
    }

    public func patternURL(_ id: UUID) -> URL { folder(id).appendingPathComponent("pattern.json") }
    public func sourcePDFURL(_ id: UUID) -> URL { folder(id).appendingPathComponent("source.pdf") }

    public func photosFolder(_ id: UUID) -> URL { folder(id).appendingPathComponent("photos", isDirectory: true) }

    /// A pattern's sample photos, in the order they were added.
    public func photos(_ id: UUID) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: photosFolder(id), includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        return files.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Copies photos in after any already there, numbered so they stay in order.
    @discardableResult
    public func addPhotos(_ urls: [URL], to id: UUID) throws -> [URL] {
        let fm = FileManager.default
        try fm.createDirectory(at: photosFolder(id), withIntermediateDirectories: true)
        var next = (photos(id).compactMap { Int($0.lastPathComponent.prefix(3)) }.max() ?? 0) + 1
        var added: [URL] = []
        for url in urls {
            let dest = photosFolder(id).appendingPathComponent(String(format: "%03d ", next) + url.lastPathComponent)
            try fm.copyItem(at: url, to: dest)
            added.append(dest)
            next += 1
        }
        return added
    }

    /// Moves one of a pattern's photos to the Trash.
    public func removePhoto(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

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

    /// Saves a pattern built in the app (e.g. from an imported PDF) into the library.
    public func importPattern(_ pattern: Pattern, sourcePDF: URL?, into index: inout LibraryIndex) throws -> PatternEntry {
        try pattern.validate()
        let id = UUID()
        let fm = FileManager.default
        try fm.createDirectory(at: folder(id), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(pattern).write(to: patternURL(id), options: .atomic)
        if let pdf = sourcePDF {
            try fm.copyItem(at: pdf, to: sourcePDFURL(id))
        }
        let entry = PatternEntry(id: id, name: pattern.name, designer: pattern.designer, addedAt: Date(), hasSourcePDF: sourcePDF != nil)
        index.patterns.append(entry)
        try save(index)
        return entry
    }

    /// Replaces a pattern's file, e.g. after its design is edited.
    public func replacePattern(_ id: UUID, with pattern: Pattern, in index: inout LibraryIndex) throws {
        try pattern.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(pattern).write(to: patternURL(id), options: .atomic)
        if let i = index.patterns.firstIndex(where: { $0.id == id }) {
            index.patterns[i].name = pattern.name
            index.patterns[i].designer = pattern.designer
        }
        try save(index)
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
