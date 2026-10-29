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
        }
    }
}

/// Craft Yarn Council standard body measurements (women), used to estimate
/// measurements a knitter hasn't taken and to infer a pattern's ease.
public enum StandardSizing {
    public static let source =
        "Craft Yarn Council, Standard Body Measurements – Woman (midpoints of the published cm ranges)"
    public static let sizes = ["XS", "S", "M", "L", "XL", "2X", "3X", "4X", "5X"]

    static let table: [BodyMeasure: [Double]] = [
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

    /// Standard value of `measure` for someone with this chest, or nil if the
    /// chart doesn't cover it (height, wrist, neck).
    public static func estimate(_ measure: BodyMeasure, chest: Double) -> Double? {
        if measure == .chest { return chest }
        guard let ys = table[measure], let xs = table[.chest] else { return nil }
        return Interpolation.at(xs: xs, ys: ys, x: chest)
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
