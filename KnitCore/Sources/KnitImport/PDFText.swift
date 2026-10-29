import CoreGraphics
import Foundation
import KnitCore
import PDFKit
import Vision

/// A run of text from a PDF in reading order, as the designer laid it out.
public struct Paragraph: Sendable, Equatable {
    public var text: String
    /// 1-based page number.
    public var page: Int
    /// Font size in points; headings are usually larger than body text.
    public var height: Double
    public var bold: Bool

    public init(text: String, page: Int, height: Double, bold: Bool = false) {
        self.text = text
        self.page = page
        self.height = height
        self.bold = bold
    }
}

public struct PageText: Sendable {
    public var page: Int
    public var paragraphs: [Paragraph]
    /// True when the page had no text layer and was read with OCR.
    public var ocr: Bool
}

/// Reads a PDF's text in reading order. Pattern PDFs are often laid out in
/// columns and PDFKit's own text order mixes them up, so lines are put back in
/// order from their positions on the page. Pages without text are read with OCR.
public enum PDFTextReader {
    struct Line {
        var text: String
        var rect: CGRect
        var size: Double
        var bold = false
    }

    /// With `ocr` off, pages without a text layer are left empty instead of being recognised.
    public static func read(_ url: URL, ocr allowOCR: Bool = true) throws -> [PageText] {
        guard let doc = PDFDocument(url: url) else { throw PatternError("Couldn't open \(url.lastPathComponent) as a PDF.") }
        var pages: [PageText] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            var lines = textLines(page)
            var ocr = false
            if allowOCR, lines.map(\.text.count).reduce(0, +) < 40, let recognised = try? ocrLines(page), !recognised.isEmpty {
                lines = recognised
                ocr = true
            }
            let paragraphs = layout(lines).map { Paragraph(text: $0.text, page: i + 1, height: $0.height, bold: $0.bold) }
            pages.append(PageText(page: i + 1, paragraphs: paragraphs, ocr: ocr))
        }
        return removingRepeats(pages)
    }

    static func textLines(_ page: PDFPage) -> [Line] {
        let bounds = page.bounds(for: .mediaBox)
        return (page.selection(for: bounds)?.selectionsByLine() ?? []).compactMap { s in
            let text = (s.string ?? "").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            let rect = s.bounds(for: page)
            var size = Double(rect.height)
            var bold = false
            if let a = s.attributedString, a.length > 0, let font = a.attribute(.font, at: a.length / 2, effectiveRange: nil) as? NSFont {
                size = Double(font.pointSize)
                bold = font.fontDescriptor.symbolicTraits.contains(.bold) || font.fontName.lowercased().contains("bold")
            }
            return Line(text: text, rect: rect, size: size, bold: bold)
        }
    }

    static func ocrLines(_ page: PDFPage) throws -> [Line] {
        let bounds = page.bounds(for: .mediaBox)
        let scale = 2.5
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let image = page.thumbnail(of: size, for: .mediaBox)
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: cg).perform([request])
        return (request.results ?? []).compactMap { obs in
            guard let text = obs.topCandidates(1).first?.string else { return nil }
            let b = obs.boundingBox
            let rect = CGRect(x: b.minX * bounds.width, y: b.minY * bounds.height, width: b.width * bounds.width, height: b.height * bounds.height)
            return Line(text: text, rect: rect, size: Double(rect.height) * 0.75)
        }
    }

    // MARK: Reading order

    struct Block {
        var text: String
        var height: Double
        var bold: Bool
    }

    /// Lines that start a new step even when they sit tight under the one before.
    static let stepStart = try! NSRegularExpression(
        pattern: #"^\*?\s*(?:(?:short |set[- ]?up |next |increase |decrease |short and increase |final |foundation )?(?:row|rnd|round)s?\b|repeat\b|total\b|note\b|step \d)"#,
        options: [.caseInsensitive]
    )

    static func startsStep(_ text: String) -> Bool {
        stepStart.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    /// Orders lines into paragraphs: columns left to right, top to bottom
    /// within a column, splitting where the gap between lines is wide.
    static func layout(_ lines: [Line]) -> [Block] {
        order(lines, depth: 0).flatMap(paragraphs)
    }

    /// Splits the lines into columns at a gutter, recursively. A gutter is a
    /// vertical strip that few lines cross; the lines that do cross it (titles,
    /// full-width paragraphs) cut the page into bands, and each band is read
    /// left column first, then right.
    static func order(_ lines: [Line], depth: Int) -> [[Line]] {
        guard lines.count >= 4, depth < 8, let x = gutter(lines) else { return [lines] }
        let crossing = { (l: Line) in l.rect.minX < x - 1 && l.rect.maxX > x + 1 }
        let spanning = lines.filter(crossing).sorted { $0.rect.maxY > $1.rect.maxY }
        let rest = lines.filter { !crossing($0) }
        var out: [[Line]] = []
        var top = Double.infinity
        func band(below bottom: Double) {
            let inBand = rest.filter { Double($0.rect.midY) < top && Double($0.rect.midY) >= bottom }
            let left = inBand.filter { Double($0.rect.midX) < x }
            let right = inBand.filter { Double($0.rect.midX) >= x }
            if !left.isEmpty { out += order(left, depth: depth + 1) }
            if !right.isEmpty { out += order(right, depth: depth + 1) }
        }
        for line in spanning {
            band(below: Double(line.rect.midY))
            out.append([line])
            top = Double(line.rect.midY)
        }
        band(below: -Double.infinity)
        return out
    }

    /// The x position of the clearest gutter, if there is one: crossed by at
    /// most a few lines, with at least three lines wholly on each side.
    static func gutter(_ lines: [Line]) -> Double? {
        let minX = lines.map { Double($0.rect.minX) }.min() ?? 0
        let maxX = lines.map { Double($0.rect.maxX) }.max() ?? 0
        guard maxX - minX > 60 else { return nil }
        let allowed = max(1, lines.count / 8)
        var best: (x: Double, crossing: Int, width: Double)?
        var runStart: Double?
        var runCrossing = Int.max
        var x = minX + 20
        func closeRun(at end: Double) {
            guard let start = runStart else { return }
            let width = end - start
            let mid = (start + end) / 2
            let left = lines.filter { Double($0.rect.maxX) <= mid }.count
            let right = lines.filter { Double($0.rect.minX) >= mid }.count
            if width >= 8, left >= 3, right >= 3,
               best == nil || runCrossing < best!.crossing || (runCrossing == best!.crossing && width > best!.width) {
                best = (mid, runCrossing, width)
            }
            runStart = nil
        }
        while x < maxX - 20 {
            let crossing = lines.filter { Double($0.rect.minX) < x && Double($0.rect.maxX) > x }.count
            if crossing <= allowed {
                if runStart == nil || crossing != runCrossing {
                    closeRun(at: x)
                    runStart = x
                    runCrossing = crossing
                }
            } else {
                closeRun(at: x)
            }
            x += 2
        }
        closeRun(at: x)
        return best?.x
    }

    /// Lines of one column in order, with fragments on the same baseline
    /// joined, broken into paragraphs at wide gaps, style changes and new steps.
    static func paragraphs(_ lines: [Line]) -> [Block] {
        var rows: [Line] = []
        for line in lines.sorted(by: { $0.rect.maxY > $1.rect.maxY || ($0.rect.maxY == $1.rect.maxY && $0.rect.minX < $1.rect.minX) }) {
            if var last = rows.last, abs(last.rect.midY - line.rect.midY) < min(last.rect.height, line.rect.height) * 0.5,
               line.rect.minX - last.rect.maxX < 3 * max(line.size, last.size), last.size == line.size, last.bold == line.bold {
                let parts = [last, line].sorted { $0.rect.minX < $1.rect.minX }
                last.text = parts.map(\.text).joined(separator: " ")
                last.rect = last.rect.union(line.rect)
                rows[rows.count - 1] = last
            } else {
                rows.append(line)
            }
        }
        var blocks: [Block] = []
        var previous: Line?
        for row in rows {
            if let p = previous, let last = blocks.last,
               Double(p.rect.minY - row.rect.maxY) < 0.5 * Double(min(row.rect.height, p.rect.height)),
               abs(row.size - p.size) < 0.5, row.bold == p.bold, !startsStep(row.text) {
                blocks[blocks.count - 1].text = join(last.text, row.text)
            } else {
                blocks.append(Block(text: row.text, height: row.size, bold: row.bold))
            }
            previous = row
        }
        return blocks
    }

    /// Joins two lines of a paragraph, mending words split across them.
    static func join(_ a: String, _ b: String) -> String {
        if a.hasSuffix("-"), let first = b.first, first.isLowercase, !a.hasSuffix(" -") {
            // "V-" + "neck" keeps the hyphen; a soft hyphen in "pat-" + "tern" can't be told apart, so keep it too.
            return a + b
        }
        return a + " " + b
    }

    // MARK: Boilerplate

    /// Drops copyright lines, page numbers and other text repeated on most pages.
    static func removingRepeats(_ pages: [PageText]) -> [PageText] {
        func key(_ s: String) -> String { s.lowercased().filter { $0.isLetter } }
        var counts: [String: Int] = [:]
        for page in pages {
            for k in Set(page.paragraphs.map { key($0.text) }) where k.count > 12 { counts[k, default: 0] += 1 }
        }
        let limit = max(3, (pages.count + 1) / 2)
        return pages.map { page in
            var p = page
            p.paragraphs = page.paragraphs.filter { para in
                let t = para.text.trimmingCharacters(in: .whitespaces)
                if t.allSatisfy(\.isNumber) && t.count <= 3 { return false }
                return (counts[key(t)] ?? 0) < limit || pages.count < 3
            }
            return p
        }
    }
}
