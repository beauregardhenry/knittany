import Foundation

/// Plain-text output of a regraded pattern (phase 1; the app draws its own views).
public enum TextReport {
    public static func render(_ r: GradeResult, fit: [FitTarget] = []) -> String {
        let f = r.formatter
        var out: [String] = []
        let p = r.pattern
        out.append(p.name.uppercased() + " — regraded")
        if let d = p.designer { out.append("Design by \(d)") }
        out.append("")

        out.append("FIT")
        out.append("  Your size \(r.position).")
        for t in fit {
            switch t.source {
            case .bodyPlusEase(let body, let ease, let from):
                let easeNote = switch from {
                case .designer: "designer's ease"
                case .inferred: "ease inferred from the pattern's sizes"
                case .knitter: "your ease"
                }
                out.append("  \(t.dimension.label): body \(f.length(body)) \(f.plusOrMinus(ease)) (\(easeNote)) = \(f.length(t.finished))")
            case .override:
                out.append("  \(t.dimension.label): \(f.length(t.finished)) (your choice)")
            case .designerGrading:
                break
            }
        }
        out.append("  Gauge: \(f.gauge(r.gauge))\(r.gauge == p.gauge ? " (the pattern's gauge)" : " (your gauge)")")
        out.append("")

        out.append("MEASUREMENTS")
        for s in r.schematic {
            var line = "  \(s.entry.id)  \(s.entry.label): \(f.length(s.target))"
            if abs(s.target - s.base) > 0.01 {
                line += " (designer's grading would give \(f.length(s.base)))"
            }
            if let a = s.achieved, abs(a - s.target) >= 0.5 {
                line += "; the stitch counts give \(f.length(a))"
            }
            out.append(line)
        }
        out.append("")

        if !r.warnings.isEmpty {
            out.append("CHECK BEFORE KNITTING")
            for w in r.warnings { out.append("  • \(w)") }
            out.append("")
        }

        for section in r.sections {
            out.append(section.title.uppercased())
            for line in section.lines {
                if line.hasPrefix("## ") {
                    out.append("")
                    out.append("  " + line.dropFirst(3))
                } else {
                    out.append("  " + line)
                }
            }
            out.append("")
        }
        return out.joined(separator: "\n")
    }

    public static func designerCheck(_ pattern: Pattern) throws -> String {
        var out: [String] = ["DESIGNER CHECK — \(pattern.name)", ""]

        let consistency = try DesignerCheck.consistency(pattern)
        out.append("1. Formulas against the designer's printed totals")
        if consistency.isEmpty {
            out.append("   All formulas match the designer in every size.")
        } else {
            for m in consistency {
                out.append("   \(m.size) \(m.quantity): designer \(MeasureFormatter.trim(m.designer)), formula \(MeasureFormatter.trim(m.computed))")
            }
        }
        out.append("")

        let reproduction = try DesignerCheck.reproduction(pattern)
        out.append("2. Grading to each published size's own measurements")
        if reproduction.isEmpty {
            out.append("   Every number comes back exactly as published, in all \(pattern.sizes.count) sizes.")
        } else {
            for m in reproduction {
                out.append("   \(m.size) \(m.quantity): designer \(MeasureFormatter.trim(m.designer)), regraded \(MeasureFormatter.trim(m.computed))")
            }
        }
        out.append("")

        let rows = try DesignerCheck.leaveOneOut(pattern)
        out.append("3. Hiding one size and regrading to it from the others")
        let sizes = Array(NSOrderedSet(array: rows.map(\.size))) as? [String] ?? []
        out.append("   Sizes tested: \(sizes.joined(separator: ", ")) (the smallest and largest can only be extrapolated, so they're skipped)")
        for (label, kinds) in [("Stitch counts", [QuantityKind.stitches]), ("Row counts", [.rows]), ("Repeat counts", [.count])] {
            let r = rows.filter { kinds.contains($0.kind) }
            guard !r.isEmpty else { continue }
            let exact = r.filter { abs($0.error) < 0.5 }.count
            let within1 = r.filter { abs($0.error) <= 1 }.count
            let within2 = r.filter { abs($0.error) <= 2 }.count
            var line = "   \(label): \(exact)/\(r.count) exact, \(within1) within 1, \(within2) within 2"
            if let worst = r.max(by: { abs($0.error) < abs($1.error) }), abs(worst.error) >= 0.5 {
                line += "; largest miss \(worst.quantity) in \(worst.size) (designer \(MeasureFormatter.trim(worst.designer)), "
                    + "predicted \(MeasureFormatter.trim(worst.predicted)))"
            }
            out.append(line)
        }
        let lengths = rows.filter { $0.kind == .length }
        if !lengths.isEmpty, let worst = lengths.max(by: { abs($0.error) < abs($1.error) }) {
            out.append("   Lengths: largest miss \(MeasureFormatter.trim(abs(worst.error))) cm (\(worst.quantity) in \(worst.size))")
        }
        let misses = rows.filter { $0.kind.isWhole && abs($0.error) > 2 }
        if !misses.isEmpty {
            out.append("   Misses larger than 2:")
            for m in misses {
                out.append("     \(m.size) \(m.quantity): designer \(MeasureFormatter.trim(m.designer)), predicted \(MeasureFormatter.trim(m.predicted))")
            }
        }
        return out.joined(separator: "\n")
    }
}
