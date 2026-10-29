import Foundation
import Testing
@testable import KnitCore

@Suite("Designing sweaters from scratch")
struct DesignTests {
    static var combinations: [DesignChoices] {
        var out: [DesignChoices] = []
        for construction in DesignChoices.Construction.allCases {
            for garment in [GarmentType.pullover, .cardigan] {
                for fit in DesignChoices.Fit.allCases {
                    for (finish, shape, sleeves) in [
                        (DesignChoices.Finish.rib2x2, DesignChoices.BodyShape.straight, DesignChoices.SleeveLength.full),
                        (.rib1x1, .aLine, .threeQuarter),
                        (.garter, .fitted, .elbow),
                        (.rolled, .straight, .short),
                    ] {
                        out.append(DesignChoices(
                            construction: construction, garment: garment, neck: fit == .relaxed ? .wide : .crew, fit: fit,
                            length: fit == .close ? .cropped : .hip, bodyShape: shape, sleeveLength: sleeves,
                            hem: finish, cuff: finish, neckband: finish, stripes: fit == .oversized,
                            chart: shape == .aLine || finish == .garter ? .men : .women
                        ))
                    }
                }
            }
        }
        return out
    }

    @Test func everyDesignRegradesToEverySize() throws {
        for choices in Self.combinations {
            let pattern = try Designer.pattern(from: choices)
            let grader = try Grader(pattern: pattern)
            let chests = pattern.schematic.first { $0.dimension == .chest }!.values
            let label = "\(choices.construction) \(choices.garment) \(choices.fit) \(choices.hem)"
            // Every published size, plus halfway between each pair.
            let targets = chests + zip(chests, chests.dropFirst()).map { ($0 + $1) / 2 }
            for chest in targets {
                let r = try grader.grade(GradeRequest(targets: [.chest: chest]))
                let v = r.values
                let at = "\(label) at \(chest)"
                #expect(r.warnings.filter { !$0.contains("outside the published sizes") }.isEmpty, "\(at): \(r.warnings)")
                #expect(!r.sections.flatMap(\.lines).contains { $0.contains("{") }, "\(at)")
                #expect(abs(v["body"]! - v["bodyT"]!) <= 6, "\(at): body \(v["body"]!) for \(v["bodyT"]!)")
                #expect(abs(v["sleeve"]! - v["armT"]!) <= 3, "\(at): sleeve \(v["sleeve"]!) for \(v["armT"]!)")
                #expect(Int(v["u"]!) % 2 == 0, "\(at): the underarm cast-on splits in two")
                let (hm, hr) = Writer(choices).multiple(choices.hem, flat: choices.garment == .cardigan)
                #expect(Int(v["hemAdjCount"]!) % hm == hr % hm, "\(at): hem count fits the \(choices.hem)")
                #expect(Int(v["cuffAdjCount"]!) % Writer(choices).multiple(choices.cuff, flat: false).0 == 0, "\(at)")
                #expect(v["sDecs"]! >= 0 && v["afterSleeve"]! >= v["cuffGoal"]! - 1, "\(at)")
                if choices.construction == .yoke {
                    #expect(v["r1"]! < v["r2"]! && v["r2"]! < v["r3"]! && v["r3"]! <= v["D"]!, "\(at): yoke increases in order")
                    #expect(v["T"] == v["n6"], "\(at)")
                } else {
                    #expect(v["afterYoke"] == v["frontY"]! + v["backY"]! + 2 * v["sleeveY"]!, "\(at)")
                    #expect(v["X"]! <= (v["D"]! - 2 * v["wF"]!) / 2, "\(at): the in-between increases fit in the yoke")
                }
            }
        }
    }

    @Test func aPersonsMeasurementsUseTheDesignEase() throws {
        let pattern = try Designer.pattern(from: DesignChoices(fit: .relaxed))
        let plan = try EaseModel.plan(for: pattern, body: [.chest: 99, .upperArm: 31])
        let chest = try #require(plan.targets.first { $0.dimension == .chest })
        #expect(chest.finished == 99 + 18)
        let arm = try #require(plan.targets.first { $0.dimension == .upperArm })
        #expect(arm.finished == 31 + 8)
    }

    @Test func mensSizesComeFromTheMensChart() throws {
        let pattern = try Designer.pattern(from: DesignChoices(fit: .classic, length: .hip, chart: .men))
        #expect(pattern.sizes == ["S", "M", "L", "XL", "2X", "3X", "4X", "5X"])
        #expect(pattern.sizedFor == .men)
        let chest = pattern.schematic.first { $0.dimension == .chest }!.values
        #expect(chest[1] == 99 + 10, "men's M is a 39 in chest plus classic ease")
        // Underarm to hip: the men's chart's back-hip length less the armhole depth.
        let length = pattern.schematic.first { $0.dimension == .bodyLength }!.values
        #expect(length[1] == 64.75 - 23.5)
    }

    @Test func estimatesFollowThePersonsChart() {
        let him = Person(name: "B", measurements: [.chest: 122], chart: .men)
        let her = Person(name: "W", measurements: [.chest: 122])
        #expect(him.estimate(.upperArm)! > her.estimate(.upperArm)! - 1)
        #expect(him.estimate(.armholeDepth)! > her.estimate(.armholeDepth)!)
        #expect(him.estimate(.backWaistLength) == nil, "the men's chart has no waist length")
        #expect(SizeChart.men.estimate(.armLength, chest: 119.5) == 50.75)
    }

    @Test func choicesRoundTrip() throws {
        let c = DesignChoices(name: "Mine", construction: .yoke, garment: .cardigan, stripes: true)
        #expect(try JSONDecoder().decode(DesignChoices.self, from: JSONEncoder().encode(c)) == c)
    }
}
