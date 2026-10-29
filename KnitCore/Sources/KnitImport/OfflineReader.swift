import Foundation
import KnitCore

/// Reads a pattern PDF without going online, using the conventions most
/// patterns share: sizes listed as "S (M, L)" or "1 [2, 3]", and every number
/// that changes with size written the same way, e.g. "CO 142 (148, 154) sts".
/// Each such number becomes a value graded along the finished measurement it
/// follows most closely, and the sentence it sits in becomes a template.
public enum OfflineReader {
    public static func read(_ pdf: URL, ocr: Bool = true) throws -> ImportDraft {
        try read(pages: PDFTextReader.read(pdf, ocr: ocr), fileName: pdf.deletingPathExtension().lastPathComponent)
    }

    public static func read(pages: [PageText], fileName: String) throws -> ImportDraft {
        var reader = Reader(paragraphs: pages.flatMap(\.paragraphs), fileName: fileName)
        let ocrPages = pages.filter(\.ocr).map(\.page)
        if !ocrPages.isEmpty {
            reader.notes.append("Pages \(ocrPages.map(String.init).joined(separator: ", ")) had no text and were read with OCR; check their numbers closely.")
        }
        return try reader.run(pages: pages)
    }
}

/// A run of per-size numbers found in a paragraph, e.g. "142 (148, 154) sts".
struct SizeRun {
    enum Unit {
        case cm, inch, yard, metre, stitches, rows, times, other
    }

    /// The text replaced by the placeholder (numbers, plus the unit for lengths and yarn).
    var range: Range<String.Index>
    var values: [Double]
    var unit: Unit?
}

struct Reader {
    var paragraphs: [Paragraph]
    var fileName: String
    var notes: [String] = []
    var sizeCount = 0
    var sizeNames: [String] = []

    init(paragraphs: [Paragraph], fileName: String) {
        self.paragraphs = paragraphs.map {
            var p = $0
            p.text = p.text.replacingOccurrences(of: "{", with: "(").replacingOccurrences(of: "}", with: ")")
            return p
        }
        self.fileName = fileName
    }

    mutating func run(pages: [PageText]) throws -> ImportDraft {
        guard !paragraphs.isEmpty else { throw PatternError("No text was found in the PDF.") }
        let sizes = findSizes()
        sizeCount = sizes.count
        sizeNames = sizes
        let gauge = findGauge()
        let measurements = findMeasurements()
        if !measurements.contains(where: { $0.dimension == .chest }) {
            notes.append("No finished chest measurement was found. Add it under Finished measurements; it picks the size.")
        }
        var numbers = NumberTable(measurements: measurements)
        let sections = buildSections(numbers: &numbers)
        return ImportDraft(
            method: .offline,
            name: findName(),
            designer: findDesigner(),
            garment: findGarment(),
            sizes: sizes,
            gauge: gauge,
            chestEase: findEase(),
            measurements: measurements,
            numbers: numbers.numbers,
            sections: sections,
            chartPages: findChartPages(pages),
            notes: notes
        )
    }

    // MARK: Title

    func findName() -> String {
        let first = paragraphs.filter { $0.page == paragraphs[0].page }
        let name = first.max { $0.height < $1.height }?.text ?? fileName
        return name.count > 60 ? fileName : titleCase(name)
    }

    func findDesigner() -> String {
        let early = paragraphs.filter { $0.page <= paragraphs[0].page + 1 }
        for (i, p) in early.enumerated() {
            let t = p.text.trimmingCharacters(in: .whitespaces)
            if let m = firstMatch(#"^(?:designed by|design by|pattern by|by)\s*:?\s*(.*)$"#, in: t, options: .caseInsensitive) {
                var name = m[1].trimmingCharacters(in: .whitespaces)
                if name.isEmpty, i + 1 < early.count { name = early[i + 1].text }
                return titleCase(collapseLetterSpacing(Self.leadingName(name)))
            }
        }
        return ""
    }

    func findGarment() -> GarmentType? {
        let start = paragraphs.prefix(40).map(\.text).joined(separator: " ").lowercased()
        if start.contains("cardigan") { return .cardigan }
        if ["pullover", "sweater", "jumper", "tee", "top"].contains(where: { start.contains($0) }) { return .pullover }
        return nil
    }

    // MARK: Sizes

    mutating func findSizes() -> [String] {
        for (i, p) in paragraphs.enumerated() {
            guard let m = firstMatch(#"^sizes?\b\s*:?\s*(.*)$"#, in: p.text, options: .caseInsensitive) else { continue }
            var rest = m[1]
            if rest.trimmingCharacters(in: .whitespaces).isEmpty, i + 1 < paragraphs.count { rest = paragraphs[i + 1].text }
            if let list = firstMatch(#"^\s*([^\s(\[]+)\s*[(\[]([^)\]]+)[)\]]"#, in: rest) {
                let names = [list[1]] + list[2].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                if names.count > 1, names.allSatisfy({ !$0.isEmpty && $0.count <= 6 }) { return names }
            }
        }
        // No size line: count the values in the most common run.
        var counts: [Int: Int] = [:]
        for p in paragraphs {
            for run in Self.runs(in: p.text) { counts[run.values.count, default: 0] += 1 }
        }
        let n = counts.max { $0.value < $1.value }?.key ?? 1
        notes.append("The list of sizes wasn't found, so they are numbered 1 to \(n). Rename them if the pattern uses names.")
        return (1...n).map(String.init)
    }

    // MARK: Gauge

    mutating func findGauge() -> DraftGauge {
        let pattern = #"(\d+(?:\.\d+)?)\s*(?:sts|stitches|st)\b[^0-9]{0,20}?(\d+(?:\.\d+)?)\s*(?:rows|rnds|rounds|ridges)\b([^.]{0,60})"#
        for (i, p) in paragraphs.enumerated() {
            guard let m = firstMatch(pattern, in: p.text, options: .caseInsensitive),
                  var sts = Double(m[1]), var rows = Double(m[2]) else { continue }
            let after = m[3].lowercased()
            let around = (p.text + " " + (i + 1 < paragraphs.count ? paragraphs[i + 1].text : "")).lowercased()
            let per10 = after.contains("10") || after.contains("4") || after.contains("cm")
            if !per10, after.contains("inch") || after.contains("1\"") || after.contains("1″") {
                sts *= 10 / 2.54
                rows *= 10 / 2.54
            } else if !per10 {
                continue
            }
            if after.contains("ridges") { rows *= 2 }
            let stitchPattern = #"(\bst st\b|stockinette|stocking|garter|seed|moss|brioche|lace|colou?rwork|\w+ rib(?:bing)?|pattern)(?: stitch| st)?"#
            let before = String(p.text.lowercased().components(separatedBy: m[0].lowercased()).first?.suffix(60) ?? "")
            var stitch = [after, before, around].lazy.compactMap { firstMatch(stitchPattern, in: $0, options: .caseInsensitive)?[0] }.first ?? ""
            if stitch.lowercased() == "st st" { stitch = "stockinette stitch" }
            let needle = firstMatch(#"US\s*\d+(?:\.\d+)?\s*\(?\s*\d+(?:\.\d+)?\s*mm\)?|\d+(?:\.\d+)?\s*mm"#, in: around, options: .caseInsensitive)?[0] ?? ""
            return DraftGauge(stitchesPer10cm: (sts * 4).rounded() / 4, rowsPer10cm: (rows * 4).rounded() / 4, stitchPattern: stitch, needle: needle)
        }
        notes.append("The gauge wasn't found. Enter the pattern's gauge before saving; stitch counts are rescaled from it.")
        return DraftGauge(stitchesPer10cm: 20, rowsPer10cm: 28)
    }

    // MARK: Ease

    func findEase() -> Double? {
        let len = #"(\d+(?:\.\d+)?)\s*(cm|"|”|″|in(?:ches)?)?"#
        let pattern = len + #"(?:\s*/\s*"# + len + #")?\s*(?:of\s+)?(positive|negative)?\s*ease"#
        for p in paragraphs {
            guard let m = firstMatch(pattern, in: p.text, options: .caseInsensitive) else { continue }
            var cm: Double?
            for (v, u) in [(m[1], m[2]), (m[3], m[4])] {
                guard let value = Double(v) else { continue }
                if u.lowercased() == "cm" { cm = value; break }
                if !u.isEmpty, cm == nil { cm = value * 2.54 }
            }
            if let cm { return m[5].lowercased() == "negative" ? -cm : cm }
        }
        return nil
    }

    // MARK: Finished measurements

    static let measureWords: [(String, GarmentMeasure, Double)] = [
        ("across back", .chest, 2), ("chest", .chest, 1), ("bust", .chest, 1),
        ("upper arm", .upperArm, 1), ("bicep", .upperArm, 1),
        ("yoke depth", .yokeDepth, 1), ("armhole depth", .yokeDepth, 1), ("armhole", .yokeDepth, 1),
        ("sleeve length", .sleeveLength, 1), ("underarm to cuff", .sleeveLength, 1),
        ("body length", .bodyLength, 1), ("length from underarm", .bodyLength, 1), ("from underarm", .bodyLength, 1),
        ("hip", .hem, 1), ("hem", .hem, 1), ("waist", .waist, 1),
        ("cuff", .cuff, 1), ("wrist", .cuff, 1),
        ("cross back", .crossBack, 1), ("shoulder width", .crossBack, 1), ("back width", .crossBack, 1),
        ("neck width", .neckWidth, 1),
    ]

    static let instructionWords = ["until", "measures", "work ", "knit", "repeat", "row ", "rnd", "continue", "cast on", "co "]

    func findMeasurements() -> [DraftMeasurement] {
        var found: [DraftMeasurement] = []
        for (i, p) in paragraphs.enumerated() {
            for run in lengthRuns(in: p.text) {
                let sentence = Self.sentence(around: run.range, in: p.text).lowercased()
                if Self.instructionWords.contains(where: sentence.contains) { continue }
                var before = String(p.text[..<run.range.lowerBound]).lowercased()
                let after = String(p.text[run.range.upperBound...].prefix(60)).lowercased()
                let startsParagraph = before.trimmingCharacters(in: .whitespaces).count < 3
                var best: (Int, String, GarmentMeasure, Double)?
                if startsParagraph {
                    best = Self.measureWords.lazy.compactMap { w in after.range(of: w.0).map { r in (-after.distance(from: after.startIndex, to: r.lowerBound), w.0, w.1, w.2) } }
                        .max { $0.0 < $1.0 }
                    if best == nil, i > 0 { before = paragraphs[i - 1].text.lowercased() + " " + before }
                }
                let context = String(before.suffix(90))
                if best == nil {
                    for (word, dim, factor) in Self.measureWords {
                        if let r = context.range(of: word, options: .backwards) {
                            let pos = context.distance(from: context.startIndex, to: r.lowerBound)
                            if best == nil || pos > best!.0 { best = (pos, word, dim, factor) }
                        }
                    }
                }
                if best == nil {
                    best = Self.measureWords.lazy.compactMap { w in after.range(of: w.0).map { r in (-after.distance(from: after.startIndex, to: r.lowerBound), w.0, w.1, w.2) } }
                        .max { $0.0 < $1.0 }
                }
                guard let (_, word, dim, factor) = best, !found.contains(where: { $0.dimension == dim }) else { continue }
                let label = factor == 2 ? "Chest (twice the width \(word))" : dim.label
                found.append(DraftMeasurement(
                    id: String(UnicodeScalar(UInt8(97 + found.count))),
                    label: label, dimension: dim,
                    values: run.values.map { ($0 * factor * 100).rounded() / 100 }
                ))
            }
        }
        found += tableRows(excluding: found)
        return found.sorted { ($0.dimension == .chest ? 0 : 1) < ($1.dimension == .chest ? 0 : 1) }
    }

    /// Size tables written as rows, e.g. "a cm 19 19.25 19.75 …" under a schematic.
    /// Rows that repeat a measurement already found are skipped; the rest are
    /// left for the knitter to match to the schematic.
    func tableRows(excluding known: [DraftMeasurement]) -> [DraftMeasurement] {
        guard sizeCount > 1 else { return [] }
        let numbers = Array(repeating: #"(\d+(?:\.\d+)?)"#, count: sizeCount).joined(separator: #"\s+"#)
        var rows: [DraftMeasurement] = []
        for (i, p) in paragraphs.enumerated() {
            for m in allMatches(#"(?:^|\s)(?:([a-z])\s+)?cm\s+"# + numbers + #"(?=\s|$)"#, in: p.text) {
                let values = m[2...].compactMap(Double.init)
                guard values.count == sizeCount else { continue }
                if (known + rows).contains(where: { zip($0.values, values).allSatisfy { abs($0 - $1) < 0.6 } }) { continue }
                var letter = m[1]
                if letter.isEmpty, let start = p.text.range(of: m[0]) {
                    // The row's letter may sit before its inch values: "d inch 10.8 … cm 27.5 …".
                    let before = p.text[..<start.lowerBound]
                    letter = allMatches(#"(?:^|\s)([a-z])\s+inch"#, in: String(before)).last?[1] ?? ""
                }
                if letter.isEmpty, i > 0 { letter = firstMatch(#"^([a-z])\s"#, in: paragraphs[i - 1].text)?[1] ?? "" }
                let id = letter.isEmpty || rows.contains(where: { $0.id == letter }) ? "t\(rows.count + 1)" : letter
                rows.append(DraftMeasurement(id: id, label: "Measurement \(id) in the size table", dimension: nil, values: values))
            }
        }
        return rows
    }

    static func sentence(around range: Range<String.Index>, in text: String) -> String {
        let start = text[..<range.lowerBound].range(of: ". ", options: .backwards)?.upperBound ?? text.startIndex
        let end = text[range.upperBound...].range(of: ". ")?.lowerBound ?? text.endIndex
        return String(text[start..<end])
    }

    /// Per-size lengths in cm (an inch and cm pair counts once).
    func lengthRuns(in text: String) -> [SizeRun] {
        Self.merged(Self.runs(in: text), in: text).filter { $0.unit == .cm && $0.values.count == sizeCount }
    }

    // MARK: Number runs

    static let unitPattern = #"(\s*(?:cm\b|mm\b|inches\b|inch\b|in\b|"|”|″|''|yards\b|yds\b|yd\b|y\b|m\b|g\b|sts\b|stitches\b|st\b|rows\b|row\b|rnds\b|rnd\b|rounds\b|round\b|garter ridges\b|ridges\b|(?:more )?times\b))?"#

    /// "142 (148, 154) sts" or "1 [2, 3]": the first size, then the others in brackets.
    static let runPattern = try! NSRegularExpression(
        pattern: #"(?<![\d.])(\d+(?:\.\d+)?)\s*[(\[]\s*(\d+(?:\.\d+)?(?:\s*,\s*\d+(?:\.\d+)?)*)\s*[)\]]"# + unitPattern,
        options: [.caseInsensitive]
    )

    /// "52 (64) 76": every other size in brackets.
    static let alternatingRunPattern = try! NSRegularExpression(
        pattern: #"(?<![\d.])(\d+(?:\.\d+)?)((?:\s*\(\s*\d+(?:\.\d+)?\s*\)\s*\d+(?:\.\d+)?)+)(?![\d.])"# + unitPattern,
        options: [.caseInsensitive]
    )

    static func runs(in text: String) -> [SizeRun] {
        let ns = text as NSString
        let all = NSRange(location: 0, length: ns.length)
        // "52 (64) 76" also looks like a two-size "52 (64)", so the longer reading wins.
        let alternating = alternatingRunPattern.matches(in: text, range: all)
        let bracketed = runPattern.matches(in: text, range: all).filter { b in
            !alternating.contains { NSIntersectionRange($0.range, b.range).length > 0 }
        }
        return (bracketed + alternating).sorted { $0.range.location < $1.range.location }.compactMap { m in
            guard let range = Range(m.range, in: text) else { return nil }
            let first = Double(ns.substring(with: m.range(at: 1)))
            let rest = ns.substring(with: m.range(at: 2))
                .split(whereSeparator: { $0 == "," || $0 == "(" || $0 == ")" || $0 == " " })
                .compactMap { Double($0) }
            guard let first else { return nil }
            let unitText = m.range(at: 3).location == NSNotFound ? "" : ns.substring(with: m.range(at: 3)).trimmingCharacters(in: .whitespaces).lowercased()
            let unit: SizeRun.Unit?
            switch unitText {
            case "": unit = nil
            case "cm": unit = .cm
            case "mm": unit = .other
            case "in", "inch", "inches", "\"", "”", "″", "''": unit = .inch
            case "y", "yd", "yds", "yards": unit = .yard
            case "m": unit = .metre
            case "sts", "st", "stitches": unit = .stitches
            case "rows", "row", "rnds", "rnd", "rounds", "round", "ridges", "garter ridges": unit = .rows
            case _ where unitText.hasSuffix("times"): unit = .times
            default: unit = .other
            }
            // Keep "sts", "rows" and "times" in the text; lengths and yarn are rendered whole.
            var r = range
            if let u = unit, [.stitches, .rows, .times, .other].contains(u), m.range(at: 3).location != NSNotFound,
               let numbersEnd = Range(NSRange(location: m.range(at: 3).location, length: 0), in: text) {
                r = range.lowerBound..<numbersEnd.lowerBound
            }
            return SizeRun(range: r, values: [first] + rest, unit: unit)
        }
    }

    /// Joins "5.8 (5.9)″ / 14.25 (14.5) cm" into one length in cm, and
    /// "77 (87) y / 70 (80) m" into one yarn amount in metres.
    static func merged(_ runs: [SizeRun], in text: String) -> [SizeRun] {
        var out: [SizeRun] = []
        var i = 0
        while i < runs.count {
            var run = runs[i]
            if i + 1 < runs.count {
                let next = runs[i + 1]
                let between = text[run.range.upperBound..<next.range.lowerBound].trimmingCharacters(in: .whitespaces)
                let pair = Set([run.unit, next.unit].compactMap { $0 })
                if between == "/" || between == "," || between == "or" {
                    if pair == [.cm, .inch] {
                        let cm = run.unit == .cm ? run : next
                        out.append(SizeRun(range: run.range.lowerBound..<next.range.upperBound, values: cm.values, unit: .cm))
                        i += 2
                        continue
                    }
                    if pair == [.yard, .metre] {
                        let m = run.unit == .metre ? run : next
                        out.append(SizeRun(range: run.range.lowerBound..<next.range.upperBound, values: m.values, unit: .metre))
                        i += 2
                        continue
                    }
                }
            }
            switch run.unit {
            case .inch:
                run.values = run.values.map { ($0 * 2.54 * 100).rounded() / 100 }
                run.unit = .cm
            case .yard:
                run.values = run.values.map { ($0 * 0.9144).rounded() }
                run.unit = .metre
            default: break
            }
            out.append(run)
            i += 1
        }
        return out
    }

    // MARK: Sections

    static let topHeadings = [
        "instructions", "directions", "yoke", "body", "back", "front", "fronts", "left front", "right front",
        "sleeve", "sleeves", "finishing", "neckband", "neck band", "collar", "button band", "buttonband", "front band",
        "pockets", "pocket", "border", "hem", "cuffs", "cuff", "assembly", "making up", "set-up", "setup", "neckline",
    ]
    static let frontMatter = [
        "abbreviation", "material", "yarn", "needle", "notion", "gauge", "tension", "size", "technique",
        "stitch", "tools", "measurement", "note", "about", "workshop", "kit", "choose", "copyright",
    ]

    func isHeading(_ p: Paragraph, body: Double) -> (Bool, top: Bool) {
        let t = p.text.trimmingCharacters(in: .whitespaces)
        let words = t.split(separator: " ")
        guard t.count <= 45, words.count <= 6, let last = t.last, !".,;:".contains(last),
              Self.runs(in: t).isEmpty,
              t.filter(\.isLetter).count * 2 >= t.count, !(t.first?.isNumber ?? true) else { return (false, false) }
        let lower = t.lowercased()
        let known = Self.topHeadings.contains(lower) || Self.topHeadings.contains(where: { lower.hasPrefix($0 + " ") && words.count <= 3 })
        let caps = t == t.uppercased() && t.count >= 3
        let tall = p.height > body * 1.15
        if known || caps && words.count <= 4 || p.height > body * 1.35 { return (true, true) }
        let plainLowercase = t == lower && words.count <= 5 && t.count >= 4 && !t.contains(where: { $0.isNumber || ".,:;!?\"”".contains($0) })
        if tall || p.bold || plainLowercase || lower.hasSuffix(" only") || words.count <= 4 && t.first?.isUppercase == true && !t.contains(":") {
            return (true, false)
        }
        return (false, false)
    }

    mutating func buildSections(numbers: inout NumberTable) -> [DraftSection] {
        let heights = paragraphs.map(\.height).sorted()
        let body = heights[heights.count / 2]
        var sections: [DraftSection] = []
        var sizeOnly: [String] = []
        var partial = 0

        func newSection(_ title: String, include: Bool) {
            sections.append(DraftSection(id: "s\(sections.count + 1)", title: title, lines: [], include: include))
        }
        newSection("About this pattern", include: false)
        let start = instructionStart(body: body)

        for (index, p) in paragraphs.enumerated() {
            let (heading, top) = isHeading(p, body: body)
            let lower = p.text.lowercased()
            let started = index >= start
            if index == start && !heading {
                newSection("Instructions", include: true)
            }
            if heading, isSizeList(p.text) {
                sizeOnly.append(p.text)
                sections[sections.count - 1].lines.append("## For sizes " + p.text)
                continue
            }
            if heading {
                let title = titleCase(p.text)
                if lower.hasSuffix(" only") { sizeOnly.append(p.text) }
                let isFront = Self.frontMatter.contains(where: { lower.contains($0) }) && !Self.topHeadings.contains(lower)
                if top || index == start || (!started && sections.last?.lines.isEmpty == false) {
                    newSection(title, include: started && !isFront)
                } else {
                    sections[sections.count - 1].lines.append("## " + title)
                }
                continue
            }
            var line = p.text
            let runs = Self.merged(Self.runs(in: p.text), in: p.text)
            for run in runs.reversed() where run.values.count == sizeCount {
                let id = numbers.id(for: run, context: p.text, section: sections[sections.count - 1].title)
                let format = run.unit == .cm ? ":len" : run.unit == .metre ? ":yarn" : ""
                line.replaceSubrange(run.range, with: "{\(id)\(format)}")
            }
            if runs.contains(where: { $0.values.count != sizeCount && $0.values.count > 1 })
                || firstMatch(#"(?:^|(?<!\d)\s+)\[\s*\d+(?:\.\d+)?(?:\s*,\s*\d+(?:\.\d+)?)+\s*\]"#, in: p.text) != nil {
                partial += 1
            }
            sections[sections.count - 1].lines.append(line)
        }
        sections.removeAll { $0.lines.isEmpty }
        if !sizeOnly.isEmpty {
            notes.append("Some steps are for certain sizes only (\(sizeOnly.prefix(3).joined(separator: "; "))). They're kept as written, so check which ones apply to the regraded size.")
        }
        if partial > 0 {
            notes.append("\(partial) instruction\(partial == 1 ? " has" : "s have") numbers for only some sizes; they're kept as written.")
        }
        return sections
    }

    /// "XXS, M2, L2, XL" or "all sizes": a label for steps that differ by size.
    func isSizeList(_ text: String) -> Bool {
        let names = Set(sizeNames.map { $0.lowercased() })
        let parts = text.lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return text.lowercased() == "all sizes" || (!parts.isEmpty && parts.allSatisfy(names.contains))
    }

    /// Where the knitting starts: an "Instructions" heading, else the heading
    /// above the first cast-on, else the first section heading.
    func instructionStart(body: Double) -> Int {
        if let i = paragraphs.firstIndex(where: { p in
            let l = p.text.lowercased()
            return (l.contains("instruction") || l.contains("directions")) && isHeading(p, body: body).0
        }) { return i }
        if let i = paragraphs.firstIndex(where: { firstMatch(#"\b(?:CO|cast on)\s+\d"#, in: $0.text, options: .caseInsensitive) != nil }) {
            var j = i
            while j > 0 && isHeading(paragraphs[j - 1], body: body).0 { j -= 1 }
            return j
        }
        return paragraphs.firstIndex { p in
            Self.topHeadings.contains(p.text.lowercased().trimmingCharacters(in: .whitespaces)) && isHeading(p, body: body).0
        } ?? 0
    }

    // MARK: Charts

    func findChartPages(_ pages: [PageText]) -> [DraftPage] {
        pages.compactMap { page in
            let text = page.paragraphs.map(\.text).joined(separator: " ")
            let words = text.split(separator: " ").count
            let mentionsChart = text.range(of: #"\bchart\b"#, options: [.regularExpression, .caseInsensitive]) != nil && text.filter(\.isLetter).count < 700
            let labelledArt = page.page > 1 && words <= 12
                && text.range(of: #"chart|pattern|colou?r ?work|motif|lace|key|legend"#, options: [.regularExpression, .caseInsensitive]) != nil
            guard mentionsChart || labelledArt, let r = text.range(of: #"\S"#, options: .regularExpression) else { return nil }
            _ = r
            let title = page.paragraphs.first { $0.text.range(of: "chart", options: .caseInsensitive) != nil }?.text ?? page.paragraphs[0].text
            return DraftPage(title: String(titleCase(title).prefix(40)), page: page.page)
        }
    }

    // MARK: Text helpers

    func titleCase(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t == t.lowercased() || t == t.uppercased() {
            return t.lowercased().split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        }
        return t
    }

    /// The capitalised words at the start, up to where a sentence begins:
    /// "STEPHEN WEST Gather your…" → "STEPHEN WEST".
    static func leadingName(_ s: String) -> String {
        let words = s.split(separator: " ")
        if words.allSatisfy({ $0.count == 1 }) { return s }
        var out: [Substring] = []
        for (i, w) in words.enumerated() {
            guard let first = w.first, first.isUppercase, out.count < 4 else { break }
            if i + 1 < words.count, words[i + 1].first?.isLowercase == true { break }
            out.append(w)
        }
        return out.isEmpty ? s : out.joined(separator: " ")
    }

    /// "K A T R I N" → "KATRIN".
    func collapseLetterSpacing(_ s: String) -> String {
        let parts = s.split(separator: " ")
        return parts.count > 3 && parts.allSatisfy({ $0.count == 1 }) ? parts.joined() : s
    }
}

/// Collects the per-size numbers, reusing one id for the same values of the same kind.
struct NumberTable {
    var measurements: [DraftMeasurement]
    var numbers: [DraftNumber] = []
    var counts: [String: Int] = [:]

    mutating func id(for run: SizeRun, context: String, section: String = "") -> String {
        let kind = Self.kind(run, context: context)
        if let existing = numbers.first(where: { $0.kind == kind && $0.values == run.values }) { return existing.id }
        let prefix: String = switch kind {
        case .stitches: "sts"
        case .rows: "rows"
        case .length: "len"
        case .yarn: "yarn"
        case .count: "times"
        case .number: "n"
        }
        counts[prefix, default: 0] += 1
        let id = "\(prefix)\(counts[prefix]!)"
        numbers.append(DraftNumber(id: id, kind: kind, driver: driver(for: run.values, kind: kind, context: section + " " + context), values: run.values, context: context))
        return id
    }

    static func kind(_ run: SizeRun, context: String) -> QuantityKind {
        switch run.unit {
        case .cm: return .length
        case .metre: return .yarn
        case .stitches: return .stitches
        case .rows: return .rows
        case .times: return .count
        case .inch, .yard, .other, nil: break
        }
        let before = String(context[..<run.range.lowerBound].suffix(14)).lowercased()
        if before.range(of: #"(?:\b[kp]|\b[kp] to|\bco|cast on|bo|bind off|pick up and k|pick up|pu|place|total|sts:?)\s*$"#, options: .regularExpression) != nil {
            return .stitches
        }
        // "… 62 (65, 68) for each front", in a sentence counting stitches.
        let sentence = Reader.sentence(around: run.range, in: context).lowercased()
        if sentence.hasPrefix("total") || sentence.range(of: #"\bsts\b|stitches"#, options: .regularExpression) != nil,
           !sentence.contains("times"), !sentence.contains("rows"), !sentence.contains("rnds") {
            return .stitches
        }
        return .count
    }

    /// The measurement whose sizes these values follow most closely.
    func driver(for values: [Double], kind: QuantityKind, context: String) -> GarmentMeasure? {
        let lower = context.lowercased()
        if kind == .length {
            if lower.contains("sleeve"), measurements.contains(where: { $0.dimension == .sleeveLength }) { return .sleeveLength }
            if lower.contains("yoke") || lower.contains("armhole"), measurements.contains(where: { $0.dimension == .yokeDepth }) { return .yokeDepth }
        }
        if kind == .stitches || kind == .count {
            let has = { (d: GarmentMeasure) in measurements.contains { $0.dimension == d } }
            if lower.contains("cuff") || lower.contains("wrist"), has(.cuff) { return .cuff }
            if lower.contains("sleeve") || lower.contains("arm"), has(.upperArm) { return .upperArm }
        }
        var best: (GarmentMeasure, Double)?
        for m in measurements {
            guard let d = m.dimension, m.values.count == values.count, let r = correlation(m.values, values) else { continue }
            let score = abs(r) + (d == .chest ? 0.02 : 0)
            if best == nil || score > best!.1 { best = (d, score) }
        }
        return best?.0
    }

    func correlation(_ a: [Double], _ b: [Double]) -> Double? {
        let n = Double(a.count)
        let ma = a.reduce(0, +) / n, mb = b.reduce(0, +) / n
        let saa = a.map { ($0 - ma) * ($0 - ma) }.reduce(0, +)
        let sbb = b.map { ($0 - mb) * ($0 - mb) }.reduce(0, +)
        guard saa > 0, sbb > 0 else { return nil }
        return zip(a, b).map { ($0 - ma) * ($1 - mb) }.reduce(0, +) / (saa * sbb).squareRoot()
    }
}

/// Capture groups of every match.
func allMatches(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> [[String]] {
    guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
    let ns = text as NSString
    return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
        (0..<m.numberOfRanges).map { i in m.range(at: i).location == NSNotFound ? "" : ns.substring(with: m.range(at: i)) }
    }
}

/// Capture groups of the first match ([0] is the whole match), or nil.
func firstMatch(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> [String]? {
    guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
    let ns = text as NSString
    guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
    return (0..<m.numberOfRanges).map { i in
        m.range(at: i).location == NSNotFound ? "" : ns.substring(with: m.range(at: i))
    }
}
