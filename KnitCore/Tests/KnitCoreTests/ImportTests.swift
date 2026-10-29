import AppKit
import CoreText
import Foundation
import Testing
@testable import KnitCore
@testable import KnitImport

/// Writes a made-up pattern PDF laid out in two columns, the way designers do.
enum SamplePDF {
    struct Box {
        var x: Double, y: Double, width: Double
        var text: String
        var size: Double = 10
        var bold = false
    }

    static func write(_ pages: [[Box]], to url: URL) throws {
        var media = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let ctx = CGContext(url as CFURL, mediaBox: &media, nil) else { throw PatternError("no PDF context") }
        for page in pages {
            ctx.beginPDFPage(nil)
            for box in page {
                let font = box.bold ? NSFont.boldSystemFont(ofSize: box.size) : NSFont.systemFont(ofSize: box.size)
                let text = NSAttributedString(string: box.text, attributes: [.font: font])
                let setter = CTFramesetterCreateWithAttributedString(text)
                let size = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(), nil, CGSize(width: box.width, height: 2000), nil)
                let rect = CGRect(x: box.x, y: box.y - size.height, width: box.width, height: size.height)
                CTFrameDraw(CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: rect, transform: nil), nil), ctx)
            }
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }

    /// Left column: materials and the start of the back. Right column: the
    /// rest of the back and the sleeves, so reading in PDF order would mix them.
    static let pages: [[Box]] = [
        [
            Box(x: 60, y: 790, width: 470, text: "Test Cardigan", size: 24, bold: true),
            Box(x: 60, y: 750, width: 470, text: "by Made Up Designer"),
            Box(x: 60, y: 720, width: 220, text: "Sizes: S (M, L, XL)"),
            Box(x: 60, y: 690, width: 220, text: "Finished chest: 36 (40, 44, 48)\" / 91.5 (101.5, 112, 122) cm, to be worn with about 4\" / 10 cm of positive ease."),
            Box(x: 60, y: 620, width: 220, text: "Upper arm: 11 (12, 13, 14)\" / 28 (30.5, 33, 35.5) cm"),
            Box(x: 60, y: 580, width: 220, text: "Gauge: 20 sts and 28 rows = 4\" / 10 cm in stockinette stitch on US 7 (4.5 mm) needles."),
            Box(x: 60, y: 520, width: 220, text: "INSTRUCTIONS", size: 13, bold: true),
            Box(x: 60, y: 495, width: 220, text: "BACK", size: 12, bold: true),
            Box(x: 60, y: 470, width: 220, text: "CO 92 (102, 112, 122) sts."),
            Box(x: 60, y: 440, width: 220, text: "Row 1 (RS): K2, (p2, k2) to end."),
            Box(x: 60, y: 426, width: 220, text: "Row 2 (WS): P2, (k2, p2) to end."),
            Box(x: 320, y: 720, width: 220, text: "Work even until the back measures 14 (14.5, 15, 15.5)\" / 35.5 (37, 38, 39.5) cm."),
            Box(x: 320, y: 670, width: 220, text: "Repeat last 2 rows 4 (5, 6, 7) more times."),
            Box(x: 320, y: 630, width: 220, text: "SLEEVES", size: 12, bold: true),
            Box(x: 320, y: 605, width: 220, text: "CO 56 (60, 66, 70) sts and join to work in the round."),
            Box(x: 320, y: 570, width: 220, text: "Sizes M and L only"),
            Box(x: 320, y: 550, width: 220, text: "Next Rnd: K to end. [62, 68] sts."),
        ],
        [
            Box(x: 220, y: 420, width: 200, text: "Chart A", size: 14, bold: true),
        ],
    ]

    static func url() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sample-pattern-\(UUID().uuidString).pdf")
        try write(pages, to: url)
        return url
    }
}

@Suite("Reading pattern PDFs offline")
struct OfflineReaderTests {
    let draft: ImportDraft

    init() throws {
        draft = try OfflineReader.read(SamplePDF.url())
    }

    @Test func readsColumnsInOrder() throws {
        let pages = try PDFTextReader.read(SamplePDF.url())
        let texts = pages[0].paragraphs.map(\.text)
        let co = try #require(texts.firstIndex { $0.hasPrefix("CO 92") })
        let row2 = try #require(texts.firstIndex { $0.hasPrefix("Row 2") })
        let measures = try #require(texts.firstIndex { $0.hasPrefix("Work even") })
        #expect(co < row2 && row2 < measures, "\(texts)")
        #expect(texts.contains("Row 1 (RS): K2, (p2, k2) to end."), "rows sitting close together stay separate")
    }

    @Test func findsPatternFacts() {
        #expect(draft.name == "Test Cardigan")
        #expect(draft.designer == "Made Up Designer")
        #expect(draft.garment == .cardigan)
        #expect(draft.sizes == ["S", "M", "L", "XL"])
        #expect(draft.gauge.stitchesPer10cm == 20 && draft.gauge.rowsPer10cm == 28)
        #expect(draft.gauge.stitchPattern.lowercased().hasPrefix("stockinette"))
        #expect(draft.chestEase == 10)
        #expect(draft.measurements.first { $0.dimension == .chest }?.values == [91.5, 101.5, 112, 122])
        #expect(draft.measurements.first { $0.dimension == .upperArm }?.values == [28, 30.5, 33, 35.5])
        #expect(draft.chartPages.map(\.page) == [2])
    }

    @Test func turnsNumbersIntoPlaceholders() throws {
        let back = try #require(draft.sections.first { $0.title == "Back" })
        #expect(back.include)
        #expect(back.lines.contains("CO {sts1} sts."))
        let length = try #require(draft.numbers.first { $0.values == [35.5, 37, 38, 39.5] })
        #expect(length.kind == .length)
        #expect(back.lines.contains("Work even until the back measures {\(length.id):len}."))
        #expect(back.lines.contains("Repeat last 2 rows {times1} more times."))
        let sleeveCO = try #require(draft.numbers.first { $0.values == [56, 60, 66, 70] })
        #expect(sleeveCO.kind == .stitches && sleeveCO.driver == .upperArm)
        #expect(draft.notes.contains { $0.contains("certain sizes only") })
        #expect(draft.notes.contains { $0.contains("only some sizes") })
        #expect(!(draft.sections.first?.include ?? true), "the materials before the instructions are left out")
    }

    @Test func becomesARegradablePattern() throws {
        let pattern = try DraftBuilder.pattern(from: draft)
        let mismatches = try DesignerCheck.reproduction(pattern)
        #expect(mismatches.isEmpty, "\(mismatches.map { "\($0.size) \($0.quantity)" })")
        let result = try Grader(pattern: pattern).grade(GradeRequest(targets: [.chest: 107]))
        let back = try #require(result.sections.first { $0.title == "Back" })
        #expect(back.lines.contains("CO 107 sts."))
        #expect(pattern.sourcePages?.map(\.page) == [2])
    }

    @Test func explainsWhatIsMissing() {
        var d = draft
        d.measurements.removeAll { $0.dimension == .chest }
        d.sections[d.sections.count - 1].lines.append("K{nope} sts.")
        let problems = DraftBuilder.problems(d)
        #expect(problems.contains { $0.contains("finished chest") })
        #expect(problems.contains { $0.contains("{nope}") })
        #expect(throws: PatternError.self) { try DraftBuilder.pattern(from: d) }
    }
}

@Suite("Reading with Claude")
struct ClaudeReaderTests {
    @Test func schemaIsStrict() throws {
        func check(_ node: Any, _ path: String) {
            guard let dict = node as? [String: Any] else { return }
            if dict["type"] as? String == "object" {
                let props = (dict["properties"] as? [String: Any]) ?? [:]
                #expect(dict["additionalProperties"] as? Bool == false, "\(path)")
                #expect(Set((dict["required"] as? [String]) ?? []) == Set(props.keys), "\(path)")
                for (k, v) in props { check(v, path + "." + k) }
            }
            if let items = dict["items"] { check(items, path + "[]") }
            for option in (dict["anyOf"] as? [Any]) ?? [] { check(option, path + "|") }
        }
        check(ClaudeReader.schema, "draft")
        _ = try JSONSerialization.data(withJSONObject: ClaudeReader.schema)
    }

    @Test func requestAsksForStructuredOutput() throws {
        let body = ClaudeReader(apiKey: "test").body(pdf: Data("%PDF".utf8))
        #expect(body["model"] as? String == "claude-opus-5-5")
        #expect(body["stream"] as? Bool == true)
        let format = (body["output_config"] as? [String: Any])?["format"] as? [String: Any]
        #expect(format?["type"] as? String == "json_schema")
        let content = ((body["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]]) ?? []
        #expect(content.first?["type"] as? String == "document")
    }

    @Test func collectsStreamedReply() throws {
        let reply = """
            {"name":"X","designer":"","garment":null,"sizes":["S","M"],"gauge":{"stitchesPer10cm":20,"rowsPer10cm":28,"stitchPattern":"","needle":""},\
            "chestEase":null,"measurements":[{"id":"a","label":"Chest","dimension":"chest","values":[90,100]}],\
            "numbers":[{"id":"co","kind":"stitches","driver":null,"values":[180,200],"context":"CO"}],\
            "sections":[{"id":"s1","title":"Body","lines":["CO {co} sts."],"include":true}],"chartPages":[],"notes":[]}
            """
        var stream = ClaudeReader.StreamReader()
        let half = reply.index(reply.startIndex, offsetBy: reply.count / 2)
        for piece in [String(reply[..<half]), String(reply[half...])] {
            let event = try JSONSerialization.data(withJSONObject: ["type": "content_block_delta", "delta": ["type": "text_delta", "text": piece]])
            _ = try stream.handle("data: " + String(decoding: event, as: UTF8.self))
        }
        _ = try stream.handle(#"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#)
        #expect(stream.stopReason == "end_turn")
        let draft = try ClaudeReader.decode(stream.text)
        #expect(draft.method == .claude)
        let pattern = try DraftBuilder.pattern(from: draft)
        let result = try Grader(pattern: pattern).grade(GradeRequest(targets: [.chest: 95]))
        #expect(result.sections[0].lines == ["CO 190 sts."])
        #expect(throws: PatternError.self) { _ = try stream.handle(#"data: {"type":"error","error":{"message":"overloaded"}}"#) }
    }
}

@Suite("Reading the real PDFs", .enabled(if: FileManager.default.fileExists(atPath: PrivatePatterns.folder.appendingPathComponent("dipped-arms.pdf").path)))
struct RealPDFTests {
    @Test func dippedArms() throws {
        let draft = try OfflineReader.read(PrivatePatterns.folder.appendingPathComponent("dipped-arms.pdf"))
        #expect(draft.sizes == ["XXS", "XS", "S", "M1", "M2", "L1", "L2", "XL", "XXL"])
        #expect(draft.gauge.stitchesPer10cm == 24 && draft.gauge.rowsPer10cm == 34)
        #expect(draft.chestEase == 17.5)
        #expect(draft.measurements.first { $0.dimension == .chest }?.values.first == 98.25)
        #expect(draft.chartPages.map(\.page) == [9, 10, 11, 12, 13])
        #expect(draft.usedNumberIDs.count >= 25)
        let titles = draft.sections.filter(\.include).map(\.title)
        #expect(Array(titles.prefix(3)) == ["Back", "Right Front", "Left Front"], "\(titles)")
        let pattern = try DraftBuilder.pattern(from: draft)
        #expect(try DesignerCheck.reproduction(pattern).isEmpty)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: PrivatePatterns.folder.appendingPathComponent("marled-mania.pdf").path)))
    func marledMania() throws {
        let draft = try OfflineReader.read(PrivatePatterns.folder.appendingPathComponent("marled-mania.pdf"))
        #expect(draft.sizes == ["1", "2", "3"])
        #expect(draft.gauge.stitchesPer10cm == 18 && draft.gauge.rowsPer10cm == 38)
        #expect(draft.measurements.first { $0.dimension == .chest }?.values == [76, 96, 116])
        #expect(draft.notes.contains { $0.contains("certain sizes only") })
        _ = try DraftBuilder.pattern(from: draft)
    }
}
