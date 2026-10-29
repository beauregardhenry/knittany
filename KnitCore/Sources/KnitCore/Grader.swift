import Foundation

public struct GradeRequest: Sendable {
    /// Finished garment measurements to aim for, in cm. The primary dimension
    /// (chest) is required; anything left out follows the designer's grading.
    public var targets: [GarmentMeasure: Double]
    /// The knitter's gauge, if it differs from the pattern's.
    public var gauge: Gauge?
    public var options: [String: Double]
    public var units: UnitPreference

    public init(
        targets: [GarmentMeasure: Double],
        gauge: Gauge? = nil,
        options: [String: Double] = [:],
        units: UnitPreference = .cmFirst
    ) {
        self.targets = targets
        self.gauge = gauge
        self.options = options
        self.units = units
    }
}

public struct SchematicResult: Sendable {
    public var entry: SchematicEntry
    /// What we aimed for.
    public var target: Double
    /// What the designer's grading gives at this chest.
    public var base: Double
    /// What the regraded stitch counts give, when the pattern says how to work it out.
    public var achieved: Double?
}

public struct RenderedSection: Sendable {
    public var title: String
    public var lines: [String]
}

public struct GradeResult: Sendable {
    public var pattern: Pattern
    public var values: [String: Double]
    public var schematic: [SchematicResult]
    public var position: String
    public var warnings: [String]
    public var sections: [RenderedSection]
    public var gauge: Gauge
    public var options: [String: Double]
    public var formatter: MeasureFormatter
}

public struct Grader {
    public let pattern: Pattern
    let formulas: [String: Expr]

    public init(pattern: Pattern) throws {
        try pattern.validate()
        self.pattern = pattern
        var formulas: [String: Expr] = [:]
        for q in pattern.quantities {
            if let f = q.formula { formulas[q.id] = try Expr.parse(f) }
        }
        self.formulas = formulas
    }

    public func grade(_ request: GradeRequest) throws -> GradeResult {
        let options = pattern.defaultOptions.merging(request.options) { _, new in new }
        let active = try activeSchematic(options: options)
        guard let primaryEntry = active.first(where: { $0.dimension == pattern.primaryDimension }) else {
            throw PatternError("no active \(pattern.primaryDimension.rawValue) measurement")
        }
        guard let primaryTarget = request.targets[pattern.primaryDimension] else {
            throw PatternError("a finished \(pattern.primaryDimension.label.lowercased()) measurement is required")
        }
        let primaryXs = primaryEntry.values

        var base: [String: Double] = [:]
        var target: [String: Double] = [:]
        var entryFor: [GarmentMeasure: SchematicEntry] = [:]
        for s in active {
            entryFor[s.dimension] = entryFor[s.dimension] ?? s
            base[s.id] = s.dimension == pattern.primaryDimension
                ? primaryTarget
                : Interpolation.at(xs: primaryXs, ys: s.values, x: primaryTarget)
            target[s.id] = request.targets[s.dimension] ?? base[s.id]
        }

        let knitterGauge = request.gauge ?? pattern.gauge
        let stitchRatio = knitterGauge.stitchesPer10cm / pattern.gauge.stitchesPer10cm
        let rowRatio = knitterGauge.rowsPer10cm / pattern.gauge.rowsPer10cm
        let patternGauge = pattern.gauge

        let evaluator = Evaluator(
            pattern: pattern,
            formulas: formulas,
            gauge: knitterGauge,
            extra: Self.extraValues(options: options, base: base, target: target, gauge: knitterGauge)
        ) { q in
            let ys = q.values ?? Array(repeating: q.value ?? 0, count: pattern.sizes.count)
            var raw: Double
            if let d = q.driver {
                guard let e = entryFor[d], let t = target[e.id], let b = base[e.id] else {
                    throw PatternError("\(q.id) follows \(d.rawValue), which isn't on the schematic")
                }
                if q.mode == .offset {
                    let delta = t - b
                    raw = Interpolation.at(xs: primaryXs, ys: ys, x: primaryTarget)
                    switch q.kind {
                    case .stitches: raw += delta * patternGauge.stitchesPerCm
                    case .rows: raw += delta * patternGauge.rowsPerCm
                    default: raw += delta
                    }
                } else {
                    raw = Interpolation.at(xs: e.values, ys: ys, x: t)
                }
            } else {
                raw = Interpolation.at(xs: primaryXs, ys: ys, x: primaryTarget)
            }
            switch (q.kind, q.per) {
            case (_, .stitches), (.stitches, nil): raw *= stitchRatio
            case (_, .rows), (.rows, nil): raw *= rowRatio
            default: break
            }
            return Self.applyRounding(raw, q)
        }

        var values: [String: Double] = [:]
        for q in pattern.quantities {
            values[q.id] = try evaluator.value(q.id)
        }

        var warnings = evaluator.notes
        warnings += extrapolationWarnings(active: active, target: target)
        for check in pattern.checks ?? [] {
            if let w = check.when, try evaluator.condition(w) == false { continue }
            if try evaluator.condition(check.expr) == false {
                warnings.append(try render(check.message, evaluator, request.units))
            }
        }

        let schematic = try active.map { s in
            SchematicResult(
                entry: s,
                target: target[s.id] ?? 0,
                base: base[s.id] ?? 0,
                achieved: try s.achieved.map { try Expr.parse($0).evaluate(in: evaluator.scope) }
            )
        }

        var sections: [RenderedSection] = []
        for section in pattern.sections {
            if let w = section.when, try evaluator.condition(w) == false { continue }
            let lines = try section.lines
                .map { try render($0, evaluator, request.units) }
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            sections.append(RenderedSection(title: section.title, lines: lines))
        }

        return GradeResult(
            pattern: pattern,
            values: values,
            schematic: schematic,
            position: describePosition(primaryTarget, xs: primaryXs),
            warnings: warnings,
            sections: sections,
            gauge: knitterGauge,
            options: options,
            formatter: MeasureFormatter(preference: request.units)
        )
    }

    func activeSchematic(options: [String: Double]) throws -> [SchematicEntry] {
        let scope = ExpressionScope(gauge: pattern.gauge) { name in
            guard let v = options[name] else { throw ExpressionError("unknown option \(name)") }
            return v
        }
        return try pattern.schematic.filter { s in
            guard let w = s.when else { return true }
            return try Expr.parse(w).evaluate(in: scope) != 0
        }
    }

    static func extraValues(
        options: [String: Double],
        base: [String: Double],
        target: [String: Double],
        gauge: Gauge
    ) -> [String: Double] {
        var extra = options
        for (id, v) in base { extra["base_\(id)"] = v }
        for (id, v) in target { extra["target_\(id)"] = v }
        extra["stPerCm"] = gauge.stitchesPerCm
        extra["rowsPerCm"] = gauge.rowsPerCm
        return extra
    }

    static func applyRounding(_ raw: Double, _ q: Quantity) -> Double {
        if let r = q.round {
            return Expr.nearestMod(raw, r.multiple, r.remainder ?? 0)
        }
        return q.kind.isWhole ? Expr.roundHalfUp(raw) : raw
    }

    func render(_ line: String, _ evaluator: Evaluator, _ units: UnitPreference) throws -> String {
        let formatter = MeasureFormatter(preference: units)
        let hooks = Template.Hooks(
            value: { text, format in
                let expr = try Expr.parse(text)
                let v = try expr.evaluate(in: evaluator.scope)
                var kind: QuantityKind = .number
                if case .ident(let id) = expr, let q = evaluator.quantities[id] { kind = q.kind }
                switch format {
                case "len": return formatter.length(v)
                case "yarn": return formatter.yarn(v)
                case "ordinal": return MeasureFormatter.ordinal(Int(Expr.roundHalfUp(v)))
                case "int": return String(Int(Expr.roundHalfUp(v)))
                case "num": return MeasureFormatter.trim(v)
                default: break
                }
                switch kind {
                case .stitches, .rows, .count: return String(Int(Expr.roundHalfUp(v)))
                case .length: return formatter.length(v)
                case .yarn: return formatter.yarn(v)
                case .number: return MeasureFormatter.trim(v)
                }
            },
            condition: { try evaluator.condition($0) }
        )
        return try Template.render(line, hooks: hooks)
    }

    func describePosition(_ x: Double, xs: [Double]) -> String {
        let fmt = MeasureFormatter()
        let pairs = zip(pattern.sizes, xs).sorted { $0.1 < $1.1 }
        if let exact = pairs.first(where: { abs($0.1 - x) < 0.01 }) { return "matches size \(exact.0)" }
        guard let first = pairs.first, let last = pairs.last else { return "" }
        if x < first.1 { return "\(fmt.length(first.1 - x)) smaller than size \(first.0)" }
        if x > last.1 { return "\(fmt.length(x - last.1)) larger than size \(last.0)" }
        for (a, b) in zip(pairs, pairs.dropFirst()) where x < b.1 {
            return "between sizes \(a.0) and \(b.0)"
        }
        return ""
    }

    func extrapolationWarnings(active: [SchematicEntry], target: [String: Double]) -> [String] {
        let fmt = MeasureFormatter()
        var out: [String] = []
        for s in active {
            guard let t = target[s.id], let lo = s.values.min(), let hi = s.values.max() else { continue }
            // The same in every size (a length): changes are added on, not extrapolated.
            if hi - lo < 0.5 { continue }
            if t < lo - 0.01 || t > hi + 0.01 {
                out.append(
                    "\(s.label) (\(fmt.length(t))) is outside the published sizes "
                        + "(\(fmt.length(lo))–\(fmt.length(hi))), so those numbers are extrapolated. Check them carefully."
                )
            }
        }
        return out
    }
}

/// Works out quantities on demand, so formulas can refer to each other in any order.
final class Evaluator {
    let quantities: [String: Quantity]
    let formulas: [String: Expr]
    let gauge: Gauge
    let extra: [String: Double]
    let primaryValue: (Quantity) throws -> Double
    var memo: [String: Double] = [:]
    var inProgress: Set<String> = []
    var notes: [String] = []

    init(
        pattern: Pattern,
        formulas: [String: Expr],
        gauge: Gauge,
        extra: [String: Double],
        primaryValue: @escaping (Quantity) throws -> Double
    ) {
        self.quantities = Dictionary(uniqueKeysWithValues: pattern.quantities.map { ($0.id, $0) })
        self.formulas = formulas
        self.gauge = gauge
        self.extra = extra
        self.primaryValue = primaryValue
    }

    var scope: ExpressionScope {
        ExpressionScope(gauge: gauge) { [unowned self] in try self.value($0) }
    }

    func condition(_ text: String) throws -> Bool {
        try Expr.parse(text).evaluate(in: scope) != 0
    }

    func value(_ id: String) throws -> Double {
        if let v = memo[id] { return v }
        if let v = extra[id] { return v }
        guard let q = quantities[id] else { throw ExpressionError("unknown name \(id)") }
        guard inProgress.insert(id).inserted else { throw ExpressionError("\(id) depends on itself") }
        defer { inProgress.remove(id) }
        let v: Double
        if let f = formulas[id] {
            v = try f.evaluate(in: scope)
            if q.kind.isWhole && abs(v - v.rounded()) > 1e-9 {
                notes.append("Internal: \(id) came out as \(v), not a whole number.")
            }
        } else {
            v = try primaryValue(q)
        }
        memo[id] = v
        return v
    }
}
