import AppKit
import CoreText
import KnitCore
import PDFKit

/// Lays out a regraded pattern as a PDF: summary, schematic, instructions,
/// charts, then any pages of the original PDF the pattern asks for.
public enum PDFExporter {
    public struct Options: Sendable {
        public var pageSize: CGSize
        public var personName: String?
        /// The original pattern PDF, for `sourcePages`.
        public var sourcePDF: URL?

        public init(pageSize: CGSize = PDFExporter.defaultPageSize, personName: String? = nil, sourcePDF: URL? = nil) {
            self.pageSize = pageSize
            self.personName = personName
            self.sourcePDF = sourcePDF
        }
    }

    public static let letter = CGSize(width: 612, height: 792)
    public static let a4 = CGSize(width: 595, height: 842)

    public static var defaultPageSize: CGSize {
        ["US", "CA", "MX"].contains(Locale.current.region?.identifier ?? "") ? letter : a4
    }

    public static func export(_ result: GradeResult, plan: FitPlan, options: Options = Options()) throws -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: options.pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, [
                  kCGPDFContextTitle: "\(result.pattern.name) — regraded" as CFString,
                  kCGPDFContextCreator: "Knitting" as CFString,
              ] as CFDictionary)
        else { throw PatternError("couldn't create the PDF") }

        var writer = PageWriter(ctx: ctx, size: options.pageSize, footer: footer(result, options))
        writer.flow(summary(result, plan: plan, options: options))

        writer.newPage()
        writer.drawFlipped { ctx, rect in
            Ink.text("Schematic", at: CGPoint(x: rect.minX, y: rect.minY + 8), in: ctx, size: 15, bold: true, anchor: .left)
            Ink.text(
                "Measurements of the finished garment, before blocking.",
                at: CGPoint(x: rect.minX, y: rect.minY + 26), in: ctx, size: 9.5, color: Ink.faint, anchor: .left
            )
            SchematicDrawing(result: result).draw(in: ctx, rect: CGRect(x: rect.minX, y: rect.minY + 44, width: rect.width, height: rect.height * 0.62))
        }

        writer.newPage()
        writer.flow(instructions(result))

        for chart in result.charts {
            writer.newPage()
            writer.drawFlipped { ctx, rect in
                Ink.text(chart.title, at: CGPoint(x: rect.minX, y: rect.minY + 8), in: ctx, size: 15, bold: true, anchor: .left)
                ChartDrawing(chart: chart).draw(in: ctx, rect: CGRect(x: rect.minX, y: rect.minY + 30, width: rect.width, height: rect.height - 30))
            }
        }
        writer.finish()
        ctx.closePDF()

        guard !result.sourcePages.isEmpty, let url = options.sourcePDF,
              let source = PDFDocument(url: url), let out = PDFDocument(data: data as Data)
        else { return data as Data }
        for ref in result.sourcePages where ref.page >= 1 && ref.page <= source.pageCount {
            guard let page = source.page(at: ref.page - 1)?.copy() as? PDFPage else { continue }
            out.insert(page, at: out.pageCount)
        }
        return out.dataRepresentation() ?? data as Data
    }

    static func footer(_ r: GradeResult, _ o: Options) -> String {
        var s = "\(r.pattern.name)"
        if let d = r.pattern.designer { s += " by \(d)" }
        s += " — regraded"
        if let who = o.personName { s += " for \(who)" }
        return s
    }

    // MARK: Text

    static var body: NSFont { Ink.font(10) }
    static var bold: NSFont { Ink.font(10, bold: true) }

    static func paragraph(spacingBefore: CGFloat = 0, after: CGFloat = 4, indent: CGFloat = 0, tabs: [CGFloat] = []) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.paragraphSpacingBefore = spacingBefore
        p.paragraphSpacing = after
        p.headIndent = indent
        p.firstLineHeadIndent = 0
        p.lineHeightMultiple = 1.12
        p.tabStops = tabs.map { NSTextTab(textAlignment: .left, location: $0) }
        return p
    }

    static func line(_ text: String, font: NSFont = body, color: NSColor = .black, style: NSParagraphStyle = paragraph()) -> NSAttributedString {
        NSAttributedString(string: text + "\n", attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    }

    static func heading(_ text: String, first: Bool = false) -> NSAttributedString {
        line(text, font: Ink.font(13, bold: true), style: paragraph(spacingBefore: first ? 0 : 12, after: 5))
    }

    static func summary(_ r: GradeResult, plan: FitPlan, options: Options) -> NSAttributedString {
        let f = r.formatter
        let s = NSMutableAttributedString()
        s.append(line(r.pattern.name, font: Ink.font(22, bold: true), style: paragraph(after: 2)))
        var sub = r.pattern.designer.map { "Design by \($0) · " } ?? ""
        sub += "regraded"
        if let who = options.personName { sub += " for \(who)" }
        s.append(line(sub, font: Ink.font(11), color: .darkGray, style: paragraph(after: 14)))

        s.append(heading("Fit", first: true))
        s.append(line("Closest published sizes: \(r.position).", style: paragraph(after: 3)))
        for t in plan.targets {
            let text: String
            switch t.source {
            case .bodyPlusEase(let b, let e, let from):
                let easeNote = switch from {
                case .designer: "designer's ease"
                case .inferred: "ease inferred from the pattern's sizes"
                case .knitter: "your ease"
                }
                text = "\(t.dimension.label): body \(f.length(b)) \(f.plusOrMinus(e)) \(easeNote) = \(f.length(t.finished))"
            case .override:
                text = "\(t.dimension.label): \(f.length(t.finished)), as chosen"
            case .designerGrading:
                continue
            }
            s.append(line("• " + text, style: paragraph(after: 2, indent: 10)))
        }
        s.append(line(
            "Anything not measured follows the designer's grading for this chest.",
            color: .darkGray, style: paragraph(spacingBefore: 2, after: 3)
        ))
        let gaugeNote = r.gauge == r.pattern.gauge ? "the pattern's gauge" : "your gauge"
        s.append(line("Gauge: \(f.gauge(r.gauge)) (\(gaugeNote)). Knit and measure a swatch before you start.", style: paragraph(after: 3)))
        for note in plan.notes {
            s.append(line("• " + note, color: .darkGray, style: paragraph(after: 2, indent: 10)))
        }

        s.append(heading("Finished measurements"))
        let tabs = paragraph(after: 3, tabs: [24, 250, 360])
        s.append(line("\t\tThis version\tDesigner's grading", font: bold, style: tabs))
        for m in r.schematic {
            var row = "\(m.entry.id)\t\(m.entry.label)\t\(f.length(m.target))"
            row += abs(m.target - m.base) > 0.01 ? "\t\(f.length(m.base))" : "\t–"
            s.append(line(row, style: tabs))
            if let a = m.achieved, abs(a - m.target) >= 0.5 {
                s.append(line("\t\tthe stitch counts give \(f.length(a))", color: .darkGray, style: tabs))
            }
        }

        if !r.warnings.isEmpty {
            s.append(heading("Check before knitting"))
            for w in r.warnings {
                s.append(line("• " + w, color: NSColor(cgColor: Ink.accent) ?? .red, style: paragraph(after: 3, indent: 10)))
            }
        }
        return s
    }

    static func instructions(_ r: GradeResult) -> NSAttributedString {
        let s = NSMutableAttributedString()
        for (i, section) in r.sections.enumerated() {
            s.append(heading(section.title, first: i == 0))
            for l in section.lines {
                if l.hasPrefix("## ") {
                    s.append(line(String(l.dropFirst(3)), font: Ink.font(10.5, bold: true), style: paragraph(spacingBefore: 6, after: 3)))
                } else {
                    s.append(line(l, style: paragraph(after: 4)))
                }
            }
        }
        return s
    }
}

/// Keeps track of pages while text flows across them.
struct PageWriter {
    let ctx: CGContext
    let size: CGSize
    let footer: String
    let margin: CGFloat = 54
    var pageNumber = 0
    var pageOpen = false

    init(ctx: CGContext, size: CGSize, footer: String) {
        self.ctx = ctx
        self.size = size
        self.footer = footer
    }

    var content: CGRect {
        CGRect(x: margin, y: margin + 14, width: size.width - margin * 2, height: size.height - margin * 2 - 14)
    }

    mutating func newPage() {
        if pageOpen { endPage() }
        ctx.beginPDFPage(nil)
        pageOpen = true
        pageNumber += 1
    }

    mutating func endPage() {
        drawFlipped { ctx, _ in
            Ink.text(footer, at: CGPoint(x: margin, y: size.height - margin + 18), in: ctx, size: 8, color: Ink.faint, anchor: .left)
            Ink.text("\(pageNumber)", at: CGPoint(x: size.width - margin, y: size.height - margin + 18), in: ctx, size: 8, color: Ink.faint, anchor: .right)
        }
        ctx.endPDFPage()
        pageOpen = false
    }

    mutating func finish() {
        if pageOpen { endPage() }
    }

    /// Runs a y-down drawing block on the current page.
    func drawFlipped(_ draw: (CGContext, CGRect) -> Void) {
        ctx.saveGState()
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        draw(ctx, CGRect(x: margin, y: margin, width: size.width - margin * 2, height: size.height - margin * 2))
        ctx.restoreGState()
    }

    /// Flows text from the top of a new page (or the current one) across as
    /// many pages as it needs.
    mutating func flow(_ text: NSAttributedString) {
        if !pageOpen { newPage() }
        let setter = CTFramesetterCreateWithAttributedString(text)
        var start = 0
        while start < text.length {
            // Core Text draws y-up from the bottom left, which is the PDF's own system.
            let r = CGRect(x: margin, y: margin + 14, width: size.width - margin * 2, height: size.height - margin * 2 - 14)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: start, length: 0), CGPath(rect: r, transform: nil), nil)
            ctx.textMatrix = .identity
            CTFrameDraw(frame, ctx)
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else { break }
            start += visible.length
            if start < text.length { newPage() }
        }
    }
}
