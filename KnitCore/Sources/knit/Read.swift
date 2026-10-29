import Foundation
import KnitCore
import KnitImport

/// `knit read`: turns a pattern PDF into an import draft and, optionally, a pattern file.
func readPDF(_ pdf: URL, _ args: [String]) {
    var args = args
    var useAI = false
    var textOnly = false
    var draftOut: URL?
    var patternOut: URL?
    while !args.isEmpty {
        switch args.removeFirst() {
        case "--ai": useAI = true
        case "--text": textOnly = true
        case "--draft": draftOut = args.isEmpty ? nil : URL(fileURLWithPath: args.removeFirst())
        case "--pattern": patternOut = args.isEmpty ? nil : URL(fileURLWithPath: args.removeFirst())
        case let other: fail("Unknown flag \(other)\n\n\(usage)")
        }
    }
    do {
        if textOnly {
            for page in try PDFTextReader.read(pdf) {
                print("===== page \(page.page)\(page.ocr ? " (OCR)" : "")")
                for p in page.paragraphs { print("[\(Int(p.height))] \(p.text)") }
            }
            return
        }
        let draft: ImportDraft
        if useAI {
            guard let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty else {
                fail("Set ANTHROPIC_API_KEY to read with Claude.")
            }
            draft = try runBlocking { try await ClaudeReader(apiKey: key).read(pdf) { _ in } }
        } else {
            draft = try OfflineReader.read(pdf)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let draftOut { try encoder.encode(draft).write(to: draftOut) }
        print(DraftSummary.text(draft))
        if let patternOut {
            let pattern = try DraftBuilder.pattern(from: draft)
            try encoder.encode(pattern).write(to: patternOut)
            print("Wrote \(patternOut.path)")
        }
    } catch {
        fail("Couldn't read \(pdf.lastPathComponent): \(error)")
    }
}

/// Runs async work from the synchronous command-line tool.
func runBlocking<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) throws -> T {
    nonisolated(unsafe) var result: Result<T, Error>?
    let done = DispatchSemaphore(value: 0)
    Task {
        do { result = .success(try await work()) } catch { result = .failure(error) }
        done.signal()
    }
    done.wait()
    return try result!.get()
}
