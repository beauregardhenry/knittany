import Foundation

/// Where a finished measurement came from.
public enum TargetSource: Sendable, Equatable {
    /// The knitter's body measurement plus ease.
    case bodyPlusEase(body: Double, ease: Double, easeFrom: EaseSource)
    /// The knitter asked for this finished measurement directly.
    case override
    /// No measurement given; follows the designer's grading for this chest.
    case designerGrading
}

public enum EaseSource: String, Sendable {
    /// The pattern states it.
    case designer
    /// Worked out by comparing the pattern's sizes with standard body measurements.
    case inferred
    /// The knitter chose it.
    case knitter
}

public struct FitTarget: Sendable {
    public var dimension: GarmentMeasure
    public var finished: Double
    public var source: TargetSource
}

/// The finished measurements to grade to, plus notes on measurements that
/// couldn't be used.
public struct FitPlan: Sendable {
    public var targets: [FitTarget]
    public var notes: [String]

    public var gradeTargets: [GarmentMeasure: Double] {
        Dictionary(targets.map { ($0.dimension, $0.finished) }) { first, _ in first }
    }
}

/// Turns body measurements into the finished measurements to grade to.
public enum EaseModel {
    public static func targets(
        for pattern: Pattern,
        body: [BodyMeasure: Double],
        easeOverrides: [GarmentMeasure: Double] = [:],
        finishedOverrides: [GarmentMeasure: Double] = [:],
        options: [String: Double] = [:]
    ) throws -> [FitTarget] {
        try plan(for: pattern, body: body, easeOverrides: easeOverrides, finishedOverrides: finishedOverrides, options: options).targets
    }

    public static func plan(
        for pattern: Pattern,
        body: [BodyMeasure: Double],
        easeOverrides: [GarmentMeasure: Double] = [:],
        finishedOverrides: [GarmentMeasure: Double] = [:],
        options: [String: Double] = [:]
    ) throws -> FitPlan {
        let grader = try Grader(pattern: pattern)
        let active = try grader.activeSchematic(options: pattern.defaultOptions.merging(options) { _, new in new })
        guard let chestEntry = active.first(where: { $0.dimension == pattern.primaryDimension }) else {
            throw PatternError("no active \(pattern.primaryDimension.rawValue) measurement")
        }
        let primary = pattern.primaryDimension
        var out: [FitTarget] = []
        var notes: [String] = []

        // Chest first: everything else is read off at this chest.
        let chestFinished: Double
        let chestEase: Double
        if let f = finishedOverrides[primary] {
            chestFinished = f
            chestEase = easeOverrides[primary] ?? pattern.statedEase?[primary] ?? 0
            out.append(FitTarget(dimension: primary, finished: f, source: .override))
        } else {
            guard let bm = primary.bodyMeasure, let b = body[bm] else {
                throw PatternError("a body \(primary.label.lowercased()) measurement is required")
            }
            let (ease, source): (Double, EaseSource) =
                if let e = easeOverrides[primary] { (e, .knitter) }
                else if let e = pattern.statedEase?[primary] { (e, .designer) }
                else { throw PatternError("this pattern doesn't state its ease; enter the ease you want") }
            chestEase = ease
            chestFinished = b + ease
            out.append(FitTarget(dimension: primary, finished: chestFinished, source: .bodyPlusEase(body: b, ease: ease, easeFrom: source)))
        }

        // The body chest each published size was designed for.
        let bodyChests = chestEntry.values.map { $0 - chestEase }

        for entry in active where entry.dimension != primary {
            let d = entry.dimension
            if out.contains(where: { $0.dimension == d }) { continue }
            if let f = finishedOverrides[d] {
                out.append(FitTarget(dimension: d, finished: f, source: .override))
                continue
            }
            guard let bm = d.bodyMeasure, let b = body[bm] else { continue }
            let ease: Double
            let source: EaseSource
            if let e = easeOverrides[d] {
                (ease, source) = (e, .knitter)
            } else if let e = pattern.statedEase?[d] {
                (ease, source) = (e, .designer)
            } else {
                let perSize = zip(entry.values, bodyChests).compactMap { finished, chest in
                    StandardSizing.estimate(bm, chest: chest).map { finished - $0 }
                }
                guard perSize.count == entry.values.count else {
                    notes.append(
                        "\(bm.label) is measured, but the pattern doesn't say how much ease the \(d.label.lowercased()) has "
                            + "and the standard charts don't cover it. Enter the \(d.label.lowercased()) ease you want to use it; "
                            + "until then it follows the designer's grading."
                    )
                    continue
                }
                ease = Interpolation.at(xs: chestEntry.values, ys: perSize, x: chestFinished)
                source = .inferred
            }
            out.append(FitTarget(dimension: d, finished: b + ease, source: .bodyPlusEase(body: b, ease: ease, easeFrom: source)))
        }
        return FitPlan(targets: out, notes: notes)
    }
}
