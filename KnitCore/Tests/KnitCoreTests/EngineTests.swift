import Foundation
import Testing
@testable import KnitCore

private let gauge = Gauge(stitchesPer10cm: 20, rowsPer10cm: 28)

private func calc(_ text: String, _ values: [String: Double] = [:]) throws -> Double {
    try Expr.parse(text).evaluate(in: ExpressionScope(gauge: gauge) { name in
        guard let v = values[name] else { throw ExpressionError("unknown \(name)") }
        return v
    })
}

private func render(_ line: String, _ values: [String: Double] = [:]) throws -> String {
    try Template.render(line, hooks: Template.Hooks(
        value: { e, _ in MeasureFormatter.trim(try calc(e, values)) },
        condition: { try calc($0, values) != 0 }
    ))
}

func loadFixture(_ name: String) throws -> Pattern {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json"))
    return try Pattern.load(from: url)
}

@Suite("Formulas")
struct ExpressionTests {
    @Test func precedenceAndComparison() throws {
        #expect(try calc("2 + 3 * 4") == 14)
        #expect(try calc("(2 + 3) * 4") == 20)
        #expect(try calc("-3 + 5") == 2)
        #expect(try calc("1 < 2 && !(3 == 4)") == 1)
        #expect(try calc("a - 2*b", ["a": 142, "b": 12]) == 118)
    }

    @Test func modAndRounding() throws {
        #expect(try calc("-1 % 3") == 2)
        #expect(try calc("round(2.5)") == 3)
        #expect(try calc("round(-2.5)") == -2)
        #expect(try calc("nearestMod(248, 3, 1)") == 247)
        #expect(try calc("nearestMod(84, 3, 1)") == 85)
        #expect(try calc("nearestMod(50, 3, 0)") == 51)
        #expect(try calc("roundTo(17, 4)") == 16)
    }

    @Test func gaugeConversions() throws {
        #expect(try calc("sts(10)") == 20)
        #expect(try calc("rows(10)") == 28)
        #expect(try calc("cm(40)") == 20)
        #expect(try calc("if(0, 1/0, 7)") == 7)
    }

    @Test func errors() {
        #expect(throws: ExpressionError.self) { try calc("1 +") }
        #expect(throws: ExpressionError.self) { try calc("nope(1)") }
        #expect(throws: ExpressionError.self) { try calc("x") }
        #expect(throws: ExpressionError.self) { try calc("1 / 0") }
    }
}

@Suite("Templates")
struct TemplateTests {
    @Test func placeholders() throws {
        #expect(try render("CO {a} sts, k{a - 2}.", ["a": 10]) == "CO 10 sts, k8.")
    }

    @Test func conditionals() throws {
        let line = "p to {if x < 0}4 sts before m{elif x > 0}2 sts before m{else}m{end}, k1"
        #expect(try render(line, ["x": -1]) == "p to 4 sts before m, k1")
        #expect(try render(line, ["x": 1]) == "p to 2 sts before m, k1")
        #expect(try render(line, ["x": 0]) == "p to m, k1")
        #expect(try render("{if 0}{if 1}no{end}{else}yes{end}") == "yes")
    }

    @Test func unbalanced() {
        #expect(throws: ExpressionError.self) { try render("{if 1}open") }
        #expect(throws: ExpressionError.self) { try render("{end}") }
    }
}

@Suite("Interpolation and units")
struct InterpolationTests {
    @Test func piecewiseLinear() {
        #expect(Interpolation.at(xs: [90, 100, 110], ys: [180, 200, 220], x: 95) == 190)
        #expect(Interpolation.at(xs: [90, 100, 110], ys: [180, 200, 220], x: 100) == 200)
        // Duplicate x values are averaged.
        #expect(Interpolation.at(xs: [20, 22, 22, 24], ys: [50, 54, 54, 58], x: 22) == 54)
        // Outside the range, extend with the overall slope.
        #expect(Interpolation.at(xs: [90, 100, 110], ys: [180, 200, 220], x: 120) == 240)
        #expect(Interpolation.at(xs: [5], ys: [7], x: 100) == 7)
    }

    @Test func formatting() {
        let f = MeasureFormatter(preference: .cmFirst)
        #expect(f.length(14.25) == "14.25 cm / 5.5″")
        #expect(MeasureFormatter(preference: .inchFirst).length(10) == "4″ / 10 cm")
        #expect(MeasureFormatter.ordinal(11) == "11th")
        #expect(MeasureFormatter.ordinal(22) == "22nd")
        #expect(MeasureFormatter.ordinal(3) == "3rd")
        #expect(MeasureFormatter.ordinal(113) == "113th")
        #expect(LengthParser.cm(from: "38in") == 38 * 2.54)
        #expect(LengthParser.cm(from: "96.5 cm") == 96.5)
        #expect(LengthParser.cm(from: "12") == 12)
        #expect(LengthParser.cm(from: "abc") == nil)
    }

    @Test func standardSizing() {
        #expect(StandardSizing.estimate(.upperArm, chest: 94) == 28)
        #expect(StandardSizing.estimate(.wrist, chest: 94) == nil)
    }
}

@Suite("Grading the test pattern")
struct GraderTests {
    @Test func reproducesPublishedSizes() throws {
        let p = try loadFixture("test-sweater")
        #expect(try DesignerCheck.consistency(p).isEmpty)
        #expect(try DesignerCheck.reproduction(p).isEmpty)
    }

    @Test func betweenAndBeyondSizes() throws {
        let g = try Grader(pattern: loadFixture("test-sweater"))
        #expect(try g.grade(GradeRequest(targets: [.chest: 95])).values["co"] == 190)
        let big = try g.grade(GradeRequest(targets: [.chest: 120]))
        #expect(big.values["co"] == 240)
        #expect(big.warnings.contains { $0.contains("outside the published sizes") })
    }

    @Test func targetedChanges() throws {
        let g = try Grader(pattern: loadFixture("test-sweater"))
        let r = try g.grade(GradeRequest(targets: [.chest: 100, .bodyLength: 40, .hem: 112]))
        #expect(r.values["bodyLen"] == 38)
        // 8 cm more hem = 16 sts = 4 increase rows of 4.
        #expect(r.values["hemExtra"] == 4)
        #expect(r.sections[0].lines.contains("Increase 4 times."))
        // The upper arm follows the chest when it isn't given.
        #expect(r.values["sleeve"] == 66)
    }

    @Test func knitterGauge() throws {
        let g = try Grader(pattern: loadFixture("test-sweater"))
        let r = try g.grade(GradeRequest(targets: [.chest: 100], gauge: Gauge(stitchesPer10cm: 22, rowsPer10cm: 30.8)))
        #expect(r.values["co"] == 220)
        #expect(r.values["repeats"] == 7) // 6 × 1.1, scaled with rows
        #expect(r.values["tucks"] == 7) // not scaled
        #expect(r.values["bodyLen"] == 33) // lengths don't change
    }

    @Test func optionsAndText() throws {
        let g = try Grader(pattern: loadFixture("test-sweater"))
        let long = try g.grade(GradeRequest(targets: [.chest: 100]))
        #expect(long.sections.map(\.title) == ["Body", "Pocket"])
        #expect(long.sections[0].lines == ["CO 200 sts.", "Work until the body measures 33 cm / 13″.", "Repeat every 6th row."])
        let short = try g.grade(GradeRequest(targets: [.chest: 100], options: ["long": 0]))
        #expect(short.sections.map(\.title) == ["Body"])
        let narrow = try g.grade(GradeRequest(targets: [.chest: 100, .upperArm: 20]))
        #expect(narrow.warnings.contains("The sleeve has only 40 sts."))
    }

    @Test func easeFromBodyMeasurements() throws {
        let p = try loadFixture("test-sweater")
        let fit = try EaseModel.targets(for: p, body: [.chest: 90, .upperArm: 28])
        let chest = try #require(fit.first { $0.dimension == .chest })
        #expect(chest.finished == 100)
        #expect(chest.source == .bodyPlusEase(body: 90, ease: 10, easeFrom: .designer))
        // Size M was designed for a 90 cm chest; standard upper arm there is
        // about 27.24 cm, so the pattern has about 5.76 cm of upper-arm ease.
        let arm = try #require(fit.first { $0.dimension == .upperArm })
        #expect(abs(arm.finished - (28 + 33 - 27.238)) < 0.01)
        #expect(throws: PatternError.self) { try EaseModel.targets(for: p, body: [:]) }
    }
}
