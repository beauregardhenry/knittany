import Foundation

public struct Gauge: Codable, Sendable, Equatable {
    public var stitchesPer10cm: Double
    public var rowsPer10cm: Double
    public var stitchPattern: String?
    public var needle: String?

    public init(stitchesPer10cm: Double, rowsPer10cm: Double, stitchPattern: String? = nil, needle: String? = nil) {
        self.stitchesPer10cm = stitchesPer10cm
        self.rowsPer10cm = rowsPer10cm
        self.stitchPattern = stitchPattern
        self.needle = needle
    }

    public var stitchesPerCm: Double { stitchesPer10cm / 10 }

    /// Why this gauge can't be a real one, if it can't: real yarns knit roughly 6 to 50
    /// stitches per 10 cm, with rows about 1 to 2 times the stitches.
    public static func problems(stitchesPer10cm sts: Double, rowsPer10cm rows: Double) -> [String] {
        var out: [String] = []
        if sts < 6 || sts > 50 {
            out.append("\(MeasureFormatter.trim(sts)) stitches per 10 cm / 4 in isn't a gauge real yarn gives (about 6 to 50). Check the pattern's gauge.")
        }
        if sts >= 6, rows < sts * 0.9 || rows > sts * 2.2 {
            out.append("\(MeasureFormatter.trim(rows)) rows per 10 cm / 4 in doesn't go with \(MeasureFormatter.trim(sts)) stitches; rows are usually 1 to 2 times the stitches (about \(MeasureFormatter.trim((sts * 1.4).rounded())) here).")
        }
        return out
    }

    public var problems: [String] { Self.problems(stitchesPer10cm: stitchesPer10cm, rowsPer10cm: rowsPer10cm) }
    public var rowsPerCm: Double { rowsPer10cm / 10 }
}

/// A finished-garment measurement, as on a pattern's schematic.
public enum GarmentMeasure: String, Codable, Sendable, CaseIterable, CodingKeyRepresentable {
    case chest
    case waist
    case hem
    case upperArm
    case cuff
    case yokeDepth
    case bodyLength
    case sleeveLength
    case crossBack
    case neckWidth
    /// Circumference of the neck opening.
    case neckOpening
    /// Around the head, for hats and hoods.
    case head

    public var label: String {
        switch self {
        case .chest: "Chest"
        case .waist: "Waist"
        case .hem: "Hem / hip"
        case .upperArm: "Upper arm"
        case .cuff: "Cuff"
        case .yokeDepth: "Yoke depth (shoulder to underarm)"
        case .bodyLength: "Body length from underarm"
        case .sleeveLength: "Sleeve length"
        case .crossBack: "Cross back"
        case .neckWidth: "Neck width"
        case .neckOpening: "Neck opening"
        case .head: "Head circumference"
        }
    }

    /// The body measurement this garment measurement is worn over, if any.
    public var bodyMeasure: BodyMeasure? {
        switch self {
        case .chest: .chest
        case .waist: .waist
        case .hem: .hip
        case .upperArm: .upperArm
        case .cuff: .wrist
        case .yokeDepth: .armholeDepth
        case .sleeveLength: .armLength
        case .crossBack: .crossBack
        case .neckOpening: .neck
        case .head: .head
        case .bodyLength, .neckWidth: nil
        }
    }
}

/// A measurement of the wearer's body.
public enum BodyMeasure: String, Codable, Sendable, CaseIterable, CodingKeyRepresentable {
    case height
    case chest
    case waist
    case hip
    case upperArm
    case wrist
    case armLength
    case crossBack
    case neck
    case backWaistLength
    case armholeDepth
    case neckToWrist
    case head

    public var label: String {
        switch self {
        case .height: "Height"
        case .chest: "Chest / bust"
        case .waist: "Waist"
        case .hip: "Hip"
        case .upperArm: "Upper arm"
        case .wrist: "Wrist"
        case .armLength: "Arm length (underarm to wrist)"
        case .crossBack: "Cross back (shoulder to shoulder)"
        case .neck: "Neck"
        case .backWaistLength: "Back waist length"
        case .armholeDepth: "Armhole depth"
        case .neckToWrist: "Centre back neck to wrist"
        case .head: "Head circumference"
        }
    }
}

/// A Craft Yarn Council chart of standard body measurements.
public enum SizeChart: String, Codable, Sendable, CaseIterable {
    case women
    case men

    public var label: String {
        switch self {
        case .women: "Women's"
        case .men: "Men's"
        }
    }

    public var source: String {
        switch self {
        case .women: "Craft Yarn Council, Standard Body Measurements – Woman (midpoints of the published cm ranges)"
        case .men: "Craft Yarn Council, Standard Body Measurements – Man (midpoints of the published inch ranges, in cm)"
        }
    }

    public var sizes: [String] {
        switch self {
        case .women: ["XS", "S", "M", "L", "XL", "2X", "3X", "4X", "5X"]
        case .men: ["S", "M", "L", "XL", "2X", "3X", "4X", "5X"]
        }
    }

    var table: [BodyMeasure: [Double]] {
        switch self {
        case .women: [
            .chest: [73.5, 83.5, 94, 104, 114.25, 124.5, 134.5, 144.5, 155],
            .neckToWrist: [67.25, 69.25, 71.75, 74.25, 74.25, 77, 78.25, 80.75, 80.75],
            .backWaistLength: [42, 43, 43.5, 44.5, 45, 45.5, 45.5, 47, 47],
            .crossBack: [36.25, 37.5, 40, 42.5, 44.5, 45.5, 45.5, 47, 47],
            .armLength: [42, 43, 43, 44.5, 44.5, 45.5, 45.5, 47, 47],
            .upperArm: [25, 26, 28, 30.5, 34.5, 39.5, 43, 47, 49.5],
            .armholeDepth: [16, 17, 18.25, 19.75, 21, 22.25, 23.5, 24.75, 26],
            .waist: [59.75, 65.5, 73.5, 84, 94, 104, 112.75, 117.75, 125.5],
            .hip: [84.75, 90.25, 99, 109, 119.25, 133.25, 138.25, 143.25, 156],
        ]
        // The men's chart's centimetres have a few copying slips, so these
        // come from its inches. It measures the back to the hip, not the waist.
        case .men: [
            .chest: [89, 99, 109.25, 119.5, 129.5, 139.75, 149.75, 160],
        .neckToWrist: [82, 84.5, 87, 89.5, 92, 94.5, 97.25, 99.75],
            .crossBack: [40, 42.5, 45, 46.25, 49.5, 52, 54, 56.5],
        .armLength: [45.75, 47, 49.5, 50.75, 52, 52, 53.25, 54.5],
            .upperArm: [30.5, 33, 38, 39.25, 42, 44.5, 47, 50.75],
        .armholeDepth: [22.25, 23.5, 24.75, 26, 28, 29.25, 30.5, 31.75],
            .waist: [73.75, 83.75, 94, 109.25, 119.5, 129.5, 139.75, 149.75],
        .hip: [91.5, 101.5, 111.75, 122, 132, 139.75, 144.75, 149.75],
        ]
        }
    }

    /// Centre back neck to the hip (men's chart only).
    var backHipLength: [Double]? {
        switch self {
        case .women: nil
        case .men: [59.75, 64.75, 67.25, 71, 73.75, 76.25, 76.25, 78.75]
        }
    }

    /// Standard value of `measure` for someone with this chest, or nil if the
    /// chart doesn't cover it (height, wrist, neck).
    public func estimate(_ measure: BodyMeasure, chest: Double) -> Double? {
        if measure == .chest { return chest }
        guard let ys = table[measure], let xs = table[.chest] else { return nil }
        return Interpolation.at(xs: xs, ys: ys, x: chest)
    }
}

/// The women's chart, which most patterns are sized to.
public enum StandardSizing {
    public static let source = SizeChart.women.source
    public static let sizes = SizeChart.women.sizes
    static let table = SizeChart.women.table

    public static func estimate(_ measure: BodyMeasure, chest: Double, chart: SizeChart = .women) -> Double? {
        chart.estimate(measure, chest: chest)
    }
}

public enum Interpolation {
    /// Piecewise-linear through the points, merging equal x values by averaging.
    /// Outside the range it extends from the nearest end point using the
    /// least-squares slope of all points, which is steadier than the last step.
    public static func at(xs: [Double], ys: [Double], x: Double) -> Double {
        precondition(xs.count == ys.count && !xs.isEmpty, "interpolation needs matching, non-empty arrays")
        let points = merged(xs: xs, ys: ys)
        guard points.count > 1, let first = points.first, let last = points.last else { return points[0].y }
        if x < first.x { return first.y + slope(points) * (x - first.x) }
        if x > last.x { return last.y + slope(points) * (x - last.x) }
        for (a, b) in zip(points, points.dropFirst()) where x <= b.x {
            return a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x)
        }
        return last.y
    }

    static func merged(xs: [Double], ys: [Double]) -> [(x: Double, y: Double)] {
        var groups: [(x: Double, sum: Double, n: Double)] = []
        for (x, y) in zip(xs, ys).sorted(by: { $0.0 < $1.0 }) {
            if let lastX = groups.last?.x, abs(lastX - x) < 1e-9 {
                groups[groups.count - 1].sum += y
                groups[groups.count - 1].n += 1
            } else {
                groups.append((x, y, 1))
            }
        }
        return groups.map { ($0.x, $0.sum / $0.n) }
    }

    static func slope(_ points: [(x: Double, y: Double)]) -> Double {
        let n = Double(points.count)
        let mx = points.map(\.x).reduce(0, +) / n
        let my = points.map(\.y).reduce(0, +) / n
        let sxx = points.map { ($0.x - mx) * ($0.x - mx) }.reduce(0, +)
        let sxy = points.map { ($0.x - mx) * ($0.y - my) }.reduce(0, +)
        return sxx == 0 ? 0 : sxy / sxx
    }
}
