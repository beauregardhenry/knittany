import Foundation
import PDFKit
import Testing
@testable import KnitCore
@testable import KnitRender

private func tempFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("knit-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func fixtureURL(_ name: String) throws -> URL {
    try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json"))
}

@Suite("Library and projects")
struct LibraryTests {
    @Test func estimatesOnlyWhatWasNotMeasured() {
        let p = Person(name: "Test", measurements: [.chest: 94, .upperArm: 30])
        #expect(p.estimate(.upperArm) == nil) // measured
        #expect(p.estimate(.waist) == 73.5) // CYC M
        #expect(p.estimate(.wrist) == nil) // not in the charts
        #expect(Person(name: "No chest").estimate(.waist) == nil)
    }

    @Test func storeRoundTrip() throws {
        let store = LibraryStore(root: try tempFolder())
        var index = try store.load()
        #expect(index == LibraryIndex())

        let entry = try store.importPattern(from: fixtureURL("test-sweater"), into: &index)
        let person = Person(name: "Wearer", measurements: [.chest: 90, .upperArm: 28], units: .inchFirst)
        index.people.append(person)
        index.projects.append(Project(name: "First", patternID: entry.id, personID: person.id, finishedOverrides: [.bodyLength: 40]))
        try store.save(index)

        let reloaded = try store.load()
        #expect(reloaded == index)
        #expect(try store.pattern(entry.id).name == "Test Sweater")

        try store.deletePattern(entry.id, from: &index)
        #expect(index.patterns.isEmpty && index.projects.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.patternURL(entry.id).path))
    }

    @Test func notesAndFavoritesSurviveSaving() throws {
        let store = LibraryStore(root: try tempFolder())
        var index = try store.load()
        let entry = try store.importPattern(from: fixtureURL("test-sweater"), into: &index)
        #expect(entry.notes.isEmpty && !entry.favorite)
        index.patterns[0].notes = "Went down a needle size for the ribbing."
        index.patterns[0].favorite = true
        try store.save(index)
        #expect(try store.load().patterns[0] == index.patterns[0])
    }

    @Test func librariesFromBeforeNotesStillLoad() throws {
        let root = try tempFolder()
        let old = #"{"people":[],"projects":[],"patterns":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Old","addedAt":0,"hasSourcePDF":false}]}"#
        try Data(old.utf8).write(to: root.appendingPathComponent("library.json"))
        let entry = try #require(try LibraryStore(root: root).load().patterns.first)
        #expect(entry.name == "Old" && entry.notes.isEmpty && !entry.favorite)
    }

    @Test func photosStayInOrder() throws {
        let store = LibraryStore(root: try tempFolder())
        var index = try store.load()
        let entry = try store.importPattern(from: fixtureURL("test-sweater"), into: &index)
        #expect(store.photos(entry.id).isEmpty)
        let originals = try tempFolder()
        let files = ["front.jpg", "back.jpg", "detail.png"].map { originals.appendingPathComponent($0) }
        for f in files { try Data([1]).write(to: f) }
        try store.addPhotos(Array(files.prefix(2)), to: entry.id)
        try store.addPhotos([files[2]], to: entry.id)
        #expect(store.photos(entry.id).map(\.lastPathComponent) == ["001 front.jpg", "002 back.jpg", "003 detail.png"])
        // The same photo can be added twice without clashing.
        try store.addPhotos([files[0]], to: entry.id)
        #expect(store.photos(entry.id).last?.lastPathComponent == "004 front.jpg")
        try store.removePhoto(store.photos(entry.id)[1])
        #expect(store.photos(entry.id).map(\.lastPathComponent) == ["001 front.jpg", "003 detail.png", "004 front.jpg"])
    }

    @Test func projectRegrade() throws {
        let pattern = try Pattern.load(from: fixtureURL("test-sweater"))
        let person = Person(name: "Wearer", measurements: [.chest: 90, .wrist: 15])
        let project = Project(name: "P", patternID: UUID(), personID: person.id, finishedOverrides: [.bodyLength: 40])
        let (result, plan) = try project.regrade(pattern: pattern, person: person)
        #expect(result.values["co"] == 200)
        #expect(result.values["bodyLen"] == 38)
        #expect(plan.targets.contains { $0.dimension == .bodyLength && $0.source == .override })
        // The fixture has no cuff measurement, so the wrist isn't used and no note is needed.
        #expect(plan.notes.isEmpty)
    }

    @Test func chartValidation() throws {
        var pattern = try Pattern.load(from: fixtureURL("test-sweater"))
        pattern.charts = [Chart(id: "x", title: "X", rows: [["k", "z"]], legend: [ChartSymbol(key: "k", label: "knit", mark: .blank)])]
        #expect(throws: PatternError.self) { try pattern.validate() }
    }
}

@Suite("PDF export")
struct ExportTests {
    func gradedFixture(chart: Bool = true, sourcePage: Bool = false) throws -> (GradeResult, FitPlan) {
        var pattern = try Pattern.load(from: fixtureURL("test-sweater"))
        if chart {
            pattern.charts = [Chart(
                id: "c", title: "Chart A",
                rows: [["k", "o", "k", "x"], ["o", "k", "x", "k"], ["k", "k", "k", "k"]],
                legend: [
                    ChartSymbol(key: "k", label: "MC", mark: .blank),
                    ChartSymbol(key: "o", label: "CC1", mark: .circle),
                    ChartSymbol(key: "x", label: "CC2", mark: .cross, color: "#C8102E"),
                ],
                inTheRound: true
            )]
        }
        if sourcePage {
            pattern.sourcePages = [SourcePage(title: "Original page 1", page: 1), SourcePage(title: "Short only", page: 1, when: "!long")]
        }
        let project = Project(name: "P", patternID: UUID())
        return try project.regrade(pattern: pattern, person: Person(name: "W", measurements: [.chest: 90]))
    }

    @Test func noSweaterSchematicForACowl() throws {
        let cowl = KnitCore.Pattern(
            name: "Cowl", sizes: ["One size"], gauge: Gauge(stitchesPer10cm: 16, rowsPer10cm: 22),
            schematic: [], quantities: [Quantity(id: "co", kind: .stitches, value: 120)], sections: [Section(title: "Cowl", lines: ["CO {co} sts."])]
        )
        try cowl.validate()
        #expect(!SchematicDrawing.fits(cowl))
        let plan = try EaseModel.plan(for: cowl, body: [:])
        let result = try Grader(pattern: cowl).grade(GradeRequest(targets: plan.gradeTargets))
        let doc = try #require(PDFDocument(data: try PDFExporter.export(result, plan: plan)))
        // Summary and instructions only.
        #expect(doc.pageCount == 2)
        #expect(!(doc.string ?? "").contains("Schematic"))
        #expect(doc.page(at: 1)?.string?.contains("CO 120 sts.") == true)
    }

    @Test func pagesInOrder() throws {
        let (result, plan) = try gradedFixture()
        let data = try PDFExporter.export(result, plan: plan, options: .init(pageSize: PDFExporter.letter, personName: "W"))
        let doc = try #require(PDFDocument(data: data))
        // Summary, schematic, instructions, one chart.
        #expect(doc.pageCount == 4)
        let summary = doc.page(at: 0)?.string ?? ""
        #expect(summary.contains("Test Sweater"))
        #expect(summary.contains("regraded for W"))
        #expect(doc.page(at: 2)?.string?.contains("CO 200 sts.") == true)
        #expect(doc.page(at: 3)?.string?.contains("Chart A") == true)
    }

    @Test func appendsOriginalPages() throws {
        let source = try tempFolder().appendingPathComponent("source.pdf")
        let (plain, plainPlan) = try gradedFixture(chart: false)
        try PDFExporter.export(plain, plan: plainPlan).write(to: source)

        let (result, plan) = try gradedFixture(chart: false, sourcePage: true)
        // The "!long" page is left out because the long version is the default.
        #expect(result.sourcePages.map(\.title) == ["Original page 1"])
        let data = try PDFExporter.export(result, plan: plan, options: .init(sourcePDF: source))
        let doc = try #require(PDFDocument(data: data))
        #expect(doc.pageCount == 4)
        #expect(doc.page(at: 3)?.string?.contains("Test Sweater") == true)
    }

    @Test func longTextFlowsAcrossPages() throws {
        var (result, plan) = try gradedFixture(chart: false)
        result.sections = [RenderedSection(title: "Long", lines: Array(repeating: "Knit a very long row of stitches.", count: 400))]
        let doc = try #require(PDFDocument(data: try PDFExporter.export(result, plan: plan)))
        #expect(doc.pageCount > 4)
        let text = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined()
        #expect(text.components(separatedBy: "Knit a very long row").count - 1 == 400)
    }

    @Test func largePrintUsesBiggerTextAndMorePages() throws {
        var (result, plan) = try gradedFixture(chart: false)
        result.sections = [RenderedSection(title: "Long", lines: Array(repeating: "Knit a very long row of stitches.", count: 300))]
        let standard = try #require(PDFDocument(data: try PDFExporter.export(result, plan: plan)))
        let large = try #require(PDFDocument(data: try PDFExporter.export(result, plan: plan, options: .init(textScale: 1.6))))
        #expect(large.pageCount > standard.pageCount)
        func instructionFontSize(_ doc: PDFDocument) -> CGFloat? {
            let page = doc.page(at: doc.pageCount - 1)!
            let text = page.attributedString
            return (text?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize
        }
        let s = try #require(instructionFontSize(standard)), l = try #require(instructionFontSize(large))
        #expect(abs(l / s - 1.6) < 0.05, "standard \(s) pt, large \(l) pt")
        // The text is all still there.
        let text = (0..<large.pageCount).compactMap { large.page(at: $0)?.string }.joined()
        #expect(text.components(separatedBy: "Knit a very long row").count - 1 == 300)
    }
}

@Suite("Schematic shapes and knitting progress")
struct ShapeAndProgressTests {
    func result(_ shape: SleeveShape) throws -> GradeResult {
        var p = try Pattern.load(from: Bundle.module.url(forResource: "test-sweater", withExtension: "json", subdirectory: "Fixtures")!)
        p.shape = shape
        return try Grader(pattern: p).grade(GradeRequest(targets: [.chest: 100]))
    }

    @Test func raglansAndYokesHaveNoShoulderLine() throws {
        let setIn = SchematicDrawing(result: try result(.setIn)).geometry()
        let raglan = SchematicDrawing(result: try result(.raglan)).geometry()
        let yoke = SchematicDrawing(result: try result(.yoke)).geometry()
        #expect(setIn.body.count == 8 && raglan.body.count == 6)
        #expect(raglan.leftSleeve[0] == raglan.body[0], "the raglan sleeve runs up to the neck")
        #expect(yoke.details.count > 5 && setIn.details.isEmpty)
    }

    @Test func progressSurvivesSaving() throws {
        var project = Project(name: "P", patternID: UUID())
        project.progress = KnittingProgress(done: [KnittingProgress.key(section: "Yoke", line: 3)], counter: 12)
        let data = try JSONEncoder().encode(project)
        #expect(try JSONDecoder().decode(Project.self, from: data) == project)
        // Projects saved before knitting mode existed still load.
        var old = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        old["progress"] = nil
        let legacy = try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: old))
        #expect(legacy.progress == nil)
    }
}

@Suite("Renamed library folder")
struct LibraryMoveTests {
    @Test func movesAnOldLibraryOnce() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("move-\(UUID().uuidString)")
        let old = base.appendingPathComponent("Knitting"), new = base.appendingPathComponent("Knittany")
        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: old.appendingPathComponent("library.json"))
        LibraryStore.moveLibrary(from: old, to: new)
        #expect(fm.fileExists(atPath: new.appendingPathComponent("library.json").path))
        #expect(!fm.fileExists(atPath: old.path))
        // A newer library is never overwritten by an old one.
        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: old.appendingPathComponent("library.json"))
        LibraryStore.moveLibrary(from: old, to: new)
        #expect(try String(contentsOf: new.appendingPathComponent("library.json"), encoding: .utf8) == "{}")
    }
}
