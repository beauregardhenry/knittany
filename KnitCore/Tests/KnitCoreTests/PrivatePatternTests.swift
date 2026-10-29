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

@Suite("Marled Mania (circular yoke)", .enabled(if: PrivatePatterns.exists("marled-mania")))
struct MarledManiaTests {
    let pattern: Pattern

    init() throws {
        pattern = try Pattern.load(from: PrivatePatterns.url("marled-mania"))
    }

    @Test func matchesTheDesigner() throws {
        #expect(try DesignerCheck.consistency(pattern).isEmpty)
        #expect(try DesignerCheck.reproduction(pattern).isEmpty)
        let missed = try DesignerCheck.leaveOneOut(pattern).filter { $0.kind.isWhole && $0.error != 0 }
        #expect(missed.isEmpty, "\(missed.map { "\($0.size) \($0.quantity)" })")
    }

    /// Between sizes the rib width is rounded and the number of ribs adjusts, so
    /// the yoke still ends at the right width and the neck stays near the designer's.
    @Test func regradesSmoothlyBetweenSizes() throws {
        let grader = try Grader(pattern: pattern)
        var lastYokeEnd = 0.0
        for finished in stride(from: 70.0, through: 125, by: 1) {
            let r = try grader.grade(GradeRequest(targets: [.chest: finished]))
            let v = r.values
            let w = try #require(v["w"]), n = try #require(v["n"]), f = try #require(v["f"])
            #expect(w >= 3 && w <= 8)
            #expect(Int(n) % 2 == 1, "an odd number of ribs keeps the 2x2 rib symmetrical")
            #expect(abs(2 * n - 166) <= 0.13 * 166, "neck \(2 * n) at \(finished)")
            #expect(f >= 15)
            #expect(v["bodyTotal"] == 2 * v["front"]! + v["back"]! + 42)
            #expect(Int(v["shortTotal"]!) % Int(2 * w) == Int(w), "the shorter body is an odd number of ribs")
            #expect(Int(v["cuff"]!) % 4 == 0)
            #expect([1, 2].contains(v["finalDec"]!))
            let yokeEnd = n * w
            #expect(yokeEnd >= lastYokeEnd - 2 * w, "yoke end \(yokeEnd) after \(lastYokeEnd) at \(finished)")
            lastYokeEnd = yokeEnd
            #expect(!r.warnings.contains { $0.hasPrefix("Internal") }, "\(r.warnings)")
            let ribbing = r.sections[0].lines.filter { $0.hasSuffix("Ribbing") }
            #expect(ribbing.count == Int(w) - 1, "one stage per rib width from 2x2 up")
        }
    }

    @Test func rendersBothVersions() throws {
        let grader = try Grader(pattern: pattern)
        for long in [0.0, 1] {
            let r = try grader.grade(GradeRequest(targets: [.chest: 100, .yokeDepth: 21], options: ["long": long]))
            let titles = r.sections.map(\.title)
            #expect(titles.contains(long == 1 ? "Decrease 1x1 Ribbing" : "Shorter Version"))
            #expect(!r.sections.flatMap(\.lines).contains { $0.contains("{") })
        }
    }
}

@Suite("Stripey raglan (top-down raglan)", .enabled(if: PrivatePatterns.exists("loupy-raglan")))
struct RaglanTests {
    let pattern: Pattern

    init() throws {
        pattern = try Pattern.load(from: PrivatePatterns.url("loupy-raglan"))
    }

    @Test func matchesTheDesigner() throws {
        #expect(try DesignerCheck.consistency(pattern).isEmpty)
        #expect(try DesignerCheck.reproduction(pattern).isEmpty)
        let missed = try DesignerCheck.leaveOneOut(pattern).filter { $0.kind.isWhole && $0.error != 0 }
        #expect(missed.isEmpty, "\(missed.map { "\($0.size) \($0.quantity) \($0.designer)→\($0.predicted)" })")
    }

    /// Raglan increases tie the bust to the upper arm; body-only or sleeve-only
    /// rows take up the difference, and the yoke depth decides how many
    /// increases go on WS rows (rapid) or how many rows are worked plain.
    @Test func fitsBustArmAndYokeIndependently() throws {
        let grader = try Grader(pattern: pattern)
        for bust in stride(from: 125.0, through: 165, by: 8) {
            for armShift in [-8.0, 0, 8] {
                for depthShift in [-5.0, 0, 6] {
                    let base = try grader.grade(GradeRequest(targets: [.chest: bust]))
                    let arm = try #require(base.schematic.first { $0.entry.dimension == .upperArm }).target + armShift
                    let depth = try #require(base.schematic.first { $0.entry.dimension == .yokeDepth }).target + depthShift
                    let r = try grader.grade(GradeRequest(targets: [.chest: bust, .upperArm: arm, .yokeDepth: depth]))
                    let v = r.values
                    let label = "bust \(bust) arm \(arm) depth \(depth)"
                    #expect(!r.warnings.contains { $0.hasPrefix("Internal") }, "\(label): \(r.warnings)")
                    #expect(v["Xb"] == 0 || v["Xs"] == 0, "\(label)")
                    #expect(abs(v["body"]! - v["bustT"]!) <= 4, "\(label): body \(v["body"]!) for \(v["bustT"]!)")
                    #expect(abs(v["sleeve"]! - v["armT"]!) <= 2, "\(label): sleeve \(v["sleeve"]!) for \(v["armT"]!)")
                    #expect(Int(v["D"]!) % 4 == 0 && Int(v["ribRow"]!) % 4 == 2, "\(label): stripes line up")
                    #expect(Int(v["ribSts"]!) % 2 == 1, "\(label): odd count for 1x1 rib")
                    #expect(v["lastSleeveDec"]! <= 96, "\(label): sleeve shaping fits the sleeve")
                    #expect(!r.sections.flatMap(\.lines).contains { $0.contains("{") }, "\(label)")
                }
            }
        }
    }
}
