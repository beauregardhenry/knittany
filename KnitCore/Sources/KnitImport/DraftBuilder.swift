import Foundation
import KnitCore

/// Turns a checked draft into a pattern the grader can regrade. Each number
/// becomes a graded quantity: stitch counts follow a width (chest, upper arm…)
/// and scale with it; lengths and row counts that follow a length keep the
/// designer's value plus whatever length the knitter adds.
public enum DraftBuilder {
    public static let lengthDimensions: Set<GarmentMeasure> = [.bodyLength, .sleeveLength, .yokeDepth]

    /// Problems that stop the draft from becoming a pattern, in words for the knitter.
    public static func problems(_ draft: ImportDraft) -> [String] {
        var out: [String] = []
        let n = draft.sizes.count
        if n == 0 { out.append("Add at least one size.") }
        if draft.name.trimmingCharacters(in: .whitespaces).isEmpty { out.append("Give the pattern a name.") }
        if draft.gauge.stitchesPer10cm <= 0 || draft.gauge.rowsPer10cm <= 0 { out.append("Enter the pattern's gauge.") }
        if draft.sizeMeasure == nil && (n > 1 || draft.measurements.contains { $0.dimension != nil }) {
            out.append("Add a finished measurement for each size and choose which one picks the size: the chest for a sweater, the head for a hat or hood, the neck opening for a cowl.")
        }
        for m in draft.measurements where m.dimension != nil && m.values.count != n {
            out.append("\(m.label) has \(m.values.count) values for \(n) sizes.")
        }
        let used = draft.usedNumberIDs
        let known = Set(draft.numbers.map(\.id))
        for id in used.subtracting(known).sorted() {
            out.append("The instructions refer to {\(id)}, which isn't in the list of numbers.")
        }
        for number in draft.numbers where used.contains(number.id) && number.values.count != n {
            out.append("\(number.id) has \(number.values.count) values for \(n) sizes.")
        }
        for section in draft.sections where section.include {
            for line in section.lines {
                do {
                    _ = try Template.render(line, hooks: .init(value: { _, _ in "" }, condition: { _ in true }))
                } catch {
                    out.append("In \(section.title): \(error)")
                }
            }
        }
        return out
    }

    public static func pattern(from draft: ImportDraft) throws -> Pattern {
        let problems = problems(draft)
        guard problems.isEmpty else { throw PatternError(problems.joined(separator: "\n")) }
        var schematic: [SchematicEntry] = []
        var seen = Set<GarmentMeasure>()
        for m in draft.measurements {
            guard let d = m.dimension, seen.insert(d).inserted else { continue }
            schematic.append(SchematicEntry(id: m.id.isEmpty ? "m\(schematic.count + 1)" : m.id, label: m.label, dimension: d, values: m.values, when: nil, achieved: nil))
        }

        let used = draft.usedNumberIDs
        let quantities: [Quantity] = draft.numbers.filter { used.contains($0.id) }.map { number in
            let constant = Set(number.values).count == 1
            let driver = number.driver.flatMap { seen.contains($0) ? $0 : nil }
            let offset = driver.map { lengthDimensions.contains($0) } == true && [.length, .rows].contains(number.kind)
            return Quantity(
                id: number.id,
                kind: number.kind,
                label: String(number.context.prefix(80)),
                values: constant ? nil : number.values,
                value: constant ? number.values.first : nil,
                driver: constant ? nil : driver,
                mode: offset ? .offset : nil,
                formula: nil,
                round: nil,
                per: nil,
                internal: nil
            )
        }

        let sections = draft.sections.filter(\.include).map { Section(title: $0.title, when: nil, lines: $0.lines) }
        let g = draft.gauge
        let pattern = Pattern(
            name: draft.name,
            designer: draft.designer.isEmpty ? nil : draft.designer,
            source: "Imported from the designer's PDF (\(draft.method == .claude ? "read with Claude" : "read offline"))",
            construction: nil,
            garment: draft.garment,
            sizes: draft.sizes,
            gauge: Gauge(
                stitchesPer10cm: g.stitchesPer10cm, rowsPer10cm: g.rowsPer10cm,
                stitchPattern: g.stitchPattern.isEmpty ? nil : g.stitchPattern, needle: g.needle.isEmpty ? nil : g.needle
            ),
            primaryDimension: draft.sizeMeasure ?? .chest,
            statedEase: draft.chestEase.flatMap { e in draft.sizeMeasure.map { [$0: e] } },
            options: nil,
            schematic: schematic,
            quantities: quantities,
            checks: nil,
            sections: sections,
            charts: nil,
            sourcePages: draft.chartPages.isEmpty ? nil : draft.chartPages.map { SourcePage(title: $0.title, page: $0.page, when: nil) }
        )
        try pattern.validate()
        // Make sure every line renders for every published size before saving.
        let grader = try Grader(pattern: pattern)
        let primary = pattern.primaryDimension
        let checks = schematic.first(where: { $0.dimension == primary })?.values ?? []
        if checks.isEmpty {
            _ = try grader.grade(GradeRequest(targets: [:]))
        }
        for value in checks {
            _ = try grader.grade(GradeRequest(targets: [primary: value]))
        }
        return pattern
    }
}
