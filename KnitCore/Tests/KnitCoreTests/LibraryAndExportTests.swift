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
}
