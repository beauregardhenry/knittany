import Foundation

/// Checks a pattern file against the designer's own numbers.
public enum DesignerCheck {
    public struct Mismatch: Sendable {
        public var size: String
        public var quantity: String
        public var designer: Double
        public var computed: Double
    }

    /// Runs every formula on the designer's numbers for each size and reports
    /// where the result differs from the total the designer printed. Catches
    /// transcription mistakes and wrong formulas.
    public static func consistency(_ pattern: Pattern) throws -> [Mismatch] {
        let grader = try Grader(pattern: pattern)
        let options = pattern.defaultOptions
        let active = try grader.activeSchematic(options: options)
        var out: [Mismatch] = []
        for i in pattern.sizes.indices {
            var finished: [String: Double] = [:]
            for s in active { finished[s.id] = s.values[i] }
            let evaluator = Evaluator(
                pattern: pattern,
                formulas: grader.formulas,
                gauge: pattern.gauge,
                extra: Grader.extraValues(options: options, base: finished, target: finished, gauge: pattern.gauge)
            ) { q in
                guard let v = q.designerValue(size: i) else { throw PatternError("\(q.id) has no designer value") }
                return v
            }
            for q in pattern.quantities where q.formula != nil {
                guard let expected = q.designerValue(size: i) else { continue }
                let got = try evaluator.value(q.id)
                if abs(got - expected) > 1e-6 {
                    out.append(Mismatch(size: pattern.sizes[i], quantity: q.id, designer: expected, computed: got))
                }
            }
        }
        return out
    }

    /// Grades to each published size's own measurements. Every number should
    /// come back exactly as the designer wrote it.
    public static func reproduction(_ pattern: Pattern) throws -> [Mismatch] {
        let grader = try Grader(pattern: pattern)
        let active = try grader.activeSchematic(options: pattern.defaultOptions)
        var out: [Mismatch] = []
        for i in pattern.sizes.indices {
            let request = GradeRequest(targets: targets(active, i))
            out += compare(try grader.grade(request), pattern, sizeIndex: i)
        }
        return out
    }

    public struct LeaveOneOutRow: Sendable {
        public var size: String
        public var quantity: String
        public var kind: QuantityKind
        public var designer: Double
        public var predicted: Double
        public var error: Double { predicted - designer }
    }

    /// Hides one published size at a time, regrades to its measurements from
    /// the remaining sizes, and compares with what the designer wrote.
    public static func leaveOneOut(_ pattern: Pattern) throws -> [LeaveOneOutRow] {
        let full = try Grader(pattern: pattern)
        let active = try full.activeSchematic(options: pattern.defaultOptions)
        var rows: [LeaveOneOutRow] = []
        guard pattern.sizes.count >= 3 else { return rows }
        for k in 1..<(pattern.sizes.count - 1) {
            let reduced = try Grader(pattern: pattern.removingSize(at: k))
            let result = try reduced.grade(GradeRequest(targets: targets(active, k)))
            for q in pattern.quantities where q.internal != true {
                guard let expected = q.designerValue(size: k), let got = result.values[q.id] else { continue }
                rows.append(LeaveOneOutRow(size: pattern.sizes[k], quantity: q.id, kind: q.kind, designer: expected, predicted: got))
            }
        }
        return rows
    }

    static func targets(_ active: [SchematicEntry], _ i: Int) -> [GarmentMeasure: Double] {
        var t: [GarmentMeasure: Double] = [:]
        for s in active where t[s.dimension] == nil { t[s.dimension] = s.values[i] }
        return t
    }

    static func compare(_ result: GradeResult, _ pattern: Pattern, sizeIndex i: Int) -> [Mismatch] {
        pattern.quantities.compactMap { q in
            guard let expected = q.designerValue(size: i), let got = result.values[q.id] else { return nil }
            return abs(got - expected) > 1e-6
                ? Mismatch(size: pattern.sizes[i], quantity: q.id, designer: expected, computed: got)
                : nil
        }
    }
}
