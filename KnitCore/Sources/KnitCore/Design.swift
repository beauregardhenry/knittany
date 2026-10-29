import Foundation

/// What the knitter chooses when designing a sweater from scratch.
public struct DesignChoices: Codable, Sendable, Equatable {
    public enum Construction: String, Codable, Sendable, CaseIterable {
        case raglan
        case yoke
    }

    public enum Neck: String, Codable, Sendable, CaseIterable {
        case crew
        case wide
    }

    public enum Fit: String, Codable, Sendable, CaseIterable {
        case close, classic, relaxed, oversized
    }

    public enum Length: String, Codable, Sendable, CaseIterable {
        case cropped, hip, tunic
    }

    public enum BodyShape: String, Codable, Sendable, CaseIterable {
        case straight
        case aLine
        case fitted
    }

    public enum SleeveLength: String, Codable, Sendable, CaseIterable {
        case short, elbow, threeQuarter, full
    }

    public enum SleeveTaper: String, Codable, Sendable, CaseIterable {
        case tapered
        case straight
    }

    public enum Finish: String, Codable, Sendable, CaseIterable {
        case rib1x1, rib2x2, garter, rolled
    }

    public var name: String
    public var construction: Construction
    public var garment: GarmentType
    public var neck: Neck
    public var fit: Fit
    public var length: Length
    public var bodyShape: BodyShape
    public var sleeveLength: SleeveLength
    public var sleeveTaper: SleeveTaper
    public var hem: Finish
    public var cuff: Finish
    public var neckband: Finish
    public var stripes: Bool
    /// The knitter's swatch gauge in stockinette.
    public var gauge: Gauge
    /// Which standard chart the sizes are drawn from; nil means women's.
    public var chart: SizeChart?

    public var sizeChart: SizeChart { chart ?? .women }

    public init(
        name: String = "", construction: Construction = .raglan, garment: GarmentType = .pullover, neck: Neck = .crew,
        fit: Fit = .classic, length: Length = .hip, bodyShape: BodyShape = .straight, sleeveLength: SleeveLength = .full,
        sleeveTaper: SleeveTaper = .tapered, hem: Finish = .rib2x2, cuff: Finish = .rib2x2, neckband: Finish = .rib2x2,
        stripes: Bool = false, gauge: Gauge = Gauge(stitchesPer10cm: 20, rowsPer10cm: 28, stitchPattern: "stockinette stitch"),
        chart: SizeChart? = nil
    ) {
        self.name = name
        self.construction = construction
        self.garment = garment
        self.neck = neck
        self.fit = fit
        self.length = length
        self.bodyShape = bodyShape
        self.sleeveLength = sleeveLength
        self.sleeveTaper = sleeveTaper
        self.hem = hem
        self.cuff = cuff
        self.neckband = neckband
        self.stripes = stripes
        self.gauge = gauge
        self.chart = chart
    }

    public var defaultName: String {
        "Top-down \(construction == .raglan ? "raglan" : "round yoke") \(garment == .cardigan ? "cardigan" : "pullover")"
    }
}

/// How the design's choices turn into finished measurements for each standard size.
public enum DesignSizing {
    public struct Row {
        public var id: String
        public var label: String
        public var dimension: GarmentMeasure
        public var values: [Double]
    }

    static func ease(_ fit: DesignChoices.Fit) -> (chest: Double, arm: Double, depth: Double) {
        switch fit {
        case .close: (5, 2, 1.5)
        case .classic: (10, 5, 2.5)
        case .relaxed: (18, 8, 4)
        case .oversized: (30, 14, 6)
        }
    }

    static func depth(_ f: DesignChoices.Finish) -> Double {
        switch f {
        case .rib1x1, .rib2x2: 5
        case .garter, .rolled: 3
        }
    }

    static func neckbandDepth(_ f: DesignChoices.Finish) -> Double {
        switch f {
        case .rib1x1, .rib2x2: 2.5
        case .garter: 2
        case .rolled: 3
        }
    }

    /// A wrist for each size; the standard charts don't give one.
    static func wrist(upperArm: Double) -> Double { 13 + 0.15 * upperArm }

    static func column(_ m: BodyMeasure, _ chart: SizeChart) -> [Double] { chart.table[m] ?? [] }

    /// Underarm to the hip bone for each size. The men's chart measures the back
    /// to the hip; the women's to the waist, about 15 cm above the hip.
    static func underarmToHip(_ chart: SizeChart) -> [Double] {
        let armhole = column(.armholeDepth, chart)
        if let hip = chart.backHipLength { return zip(hip, armhole).map { $0 - $1 } }
        return zip(column(.backWaistLength, chart), armhole).map { $0 - $1 + 15 }
    }

    public static func rows(for c: DesignChoices) -> [Row] {
        let e = ease(c.fit)
        let chart = c.sizeChart
        let chest = column(.chest, chart), arm = column(.upperArm, chart), armhole = column(.armholeDepth, chart)
        let toHip = underarmToHip(chart), armLength = column(.armLength, chart), hip = column(.hip, chart)
        let n = chest.count
        func each(_ f: (Int) -> Double) -> [Double] { (0..<n).map { ((f($0)) * 4).rounded() / 4 } }

        let finishedChest = each { chest[$0] + e.chest }
        let finishedArm = each { arm[$0] + e.arm }
        let cuffDepth = depth(c.cuff)
        let sleeveFactor: Double = switch c.sleeveLength {
        case .full: 1
        case .threeQuarter: 0.68
        case .elbow: 0.4
        case .short: 0
        }
        let lengthAdd: Double = switch c.length {
        case .cropped: -17
        case .hip: 0
        case .tunic: 15
        }

        var rows = [
            Row(id: "a", label: "Chest", dimension: .chest, values: finishedChest),
            Row(id: "b", label: "Upper arm", dimension: .upperArm, values: finishedArm),
            Row(id: "c", label: "Yoke depth", dimension: .yokeDepth, values: each { armhole[$0] + e.depth }),
            Row(id: "d", label: "Body length from underarm", dimension: .bodyLength,
                values: each { toHip[$0] + lengthAdd }),
            Row(id: "e", label: "Sleeve length from underarm", dimension: .sleeveLength,
                values: each { c.sleeveLength == .short ? 8 : max(cuffDepth + 6, armLength[$0] * sleeveFactor) }),
        ]
        let cuff: [Double] = each { i in
            let full = wrist(upperArm: arm[i]) + 4
            if c.sleeveTaper == .straight || c.sleeveLength == .short { return finishedArm[i] }
            switch c.sleeveLength {
            case .full: return full
            case .threeQuarter: return 0.45 * finishedArm[i] + 0.55 * full
            case .elbow: return 0.8 * finishedArm[i] + 0.2 * full
            case .short: return finishedArm[i]
            }
        }
        rows.append(Row(id: "f", label: "Cuff", dimension: .cuff, values: cuff))
        rows.append(Row(id: "g", label: "Hem", dimension: .hem, values: each { i in
            switch c.bodyShape {
            case .straight: finishedChest[i]
            case .aLine: finishedChest[i] + 10
            case .fitted: hip[i] + e.chest * 0.6
            }
        }))
        rows.append(Row(id: "h", label: "Neck opening", dimension: .neckOpening,
                        values: each { 0.16 * chest[$0] + 30 + (c.neck == .wide ? 14 : 0) }))
        return rows
    }

    /// Ease the design is drawn with, so a person's own measurements regrade it.
    public static func statedEase(for c: DesignChoices) -> [GarmentMeasure: Double] {
        let e = ease(c.fit)
        let chart = c.sizeChart
        let mid = chart.sizes.count / 2
        let rows = rows(for: c)
        func value(_ d: GarmentMeasure) -> Double { rows.first { $0.dimension == d }!.values[mid] }
        let arm = column(.upperArm, chart)[mid]
        return [
            .chest: e.chest,
            .upperArm: e.arm,
            .yokeDepth: e.depth,
            .hem: value(.hem) - column(.hip, chart)[mid],
            .cuff: value(.cuff) - wrist(upperArm: arm),
            .sleeveLength: value(.sleeveLength) - column(.armLength, chart)[mid],
            .neckOpening: c.neck == .wide ? 20 : 6,
        ]
    }
}
