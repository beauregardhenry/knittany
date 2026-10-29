import Foundation
import Testing
@testable import KnitCore

/// Real patterns live in the git-ignored Patterns/ folder at the repo root.
/// These tests run when the files are there and are skipped otherwise.
enum PrivatePatterns {
    static let folder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Patterns")

    static func url(_ name: String) -> URL { folder.appendingPathComponent("\(name).json") }
    static func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: url(name).path) }
}

@Suite("Dipped Arms (designer's numbers)", .enabled(if: PrivatePatterns.exists("dipped-arms")))
struct DippedArmsTests {
    let pattern: Pattern

    init() throws {
        pattern = try Pattern.load(from: PrivatePatterns.url("dipped-arms"))
    }

    @Test func formulasMatchDesignerTotals() throws {
        let mismatches = try DesignerCheck.consistency(pattern)
        #expect(mismatches.isEmpty, "\(mismatches.map { "\($0.size) \($0.quantity): \($0.designer) vs \($0.computed)" })")
    }

    @Test func reproducesEveryPublishedSize() throws {
        let mismatches = try DesignerCheck.reproduction(pattern)
        #expect(mismatches.isEmpty, "\(mismatches.map { "\($0.size) \($0.quantity): \($0.designer) vs \($0.computed)" })")
    }

    /// Hiding a size and regrading to it should land on (or next to) the
    /// designer's numbers. These limits are what the engine achieves today.
    @Test func leaveOneOutAccuracy() throws {
        let rows = try DesignerCheck.leaveOneOut(pattern).filter { $0.kind.isWhole }
        let within1 = rows.filter { abs($0.error) <= 1 }.count
        let within2 = rows.filter { abs($0.error) <= 2 }.count
        #expect(Double(within1) / Double(rows.count) >= 0.97)
        #expect(Double(within2) / Double(rows.count) >= 0.99)
        #expect(rows.allSatisfy { abs($0.error) <= 4 })
    }

    @Test func rendersEverySizeAndVersion() throws {
        let g = try Grader(pattern: pattern)
        for chest in stride(from: 90.0, through: 150, by: 2.5) {
            for long in [0.0, 1.0] {
                let r = try g.grade(GradeRequest(targets: [.chest: chest], options: ["long": long]))
                #expect(!r.warnings.contains { $0.hasPrefix("Internal") }, "chest \(chest): \(r.warnings)")
                #expect(r.sections.allSatisfy { !$0.lines.isEmpty })
            }
        }
    }
}
