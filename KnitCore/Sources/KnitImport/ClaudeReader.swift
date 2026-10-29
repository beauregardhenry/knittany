import Foundation
import KnitCore

/// Reads a pattern PDF with Claude (the optional, online way to import). The
/// PDF is sent to Anthropic's API, which sees both its text and its pages as
/// images, and the reply is an `ImportDraft` checked against a JSON schema.
public struct ClaudeReader: Sendable {
    public static let model = "claude-opus-5-5"
    public var apiKey: String
    public var endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// `progress` gets the number of characters received so far.
    public func read(_ pdf: URL, progress: @escaping @Sendable (Int) -> Void) async throws -> ImportDraft {
        let data = try Data(contentsOf: pdf)
        guard data.count < 30_000_000 else { throw PatternError("The PDF is too large to send (the limit is 30 MB).") }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 900
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body(pdf: data))

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            var text = ""
            for try await line in bytes.lines { text += line }
            throw PatternError(Self.errorMessage(status: status, body: text))
        }

        var stream = StreamReader()
        for try await line in bytes.lines {
            if try stream.handle(line) { progress(stream.text.count) }
        }
        switch stream.stopReason {
        case "refusal": throw PatternError("Claude declined to read this PDF. Try the offline import instead.")
        case "max_tokens": throw PatternError("The pattern was too long for one reply. Try the offline import instead.")
        default: break
        }
        return try Self.decode(stream.text)
    }

    /// Collects the reply text from the server-sent events of a streamed response.
    struct StreamReader {
        var text = ""
        var stopReason: String?

        /// Returns true when the line added text.
        mutating func handle(_ line: String) throws -> Bool {
            guard line.hasPrefix("data:") else { return false }
            let payload = Data(line.dropFirst(5).trimmingCharacters(in: .whitespaces).utf8)
            guard let event = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return false }
            switch event["type"] as? String {
            case "content_block_delta":
                if let delta = event["delta"] as? [String: Any], delta["type"] as? String == "text_delta", let t = delta["text"] as? String {
                    text += t
                    return true
                }
            case "message_delta":
                if let delta = event["delta"] as? [String: Any], let r = delta["stop_reason"] as? String { stopReason = r }
            case "error":
                let message = (event["error"] as? [String: Any])?["message"] as? String ?? "unknown error"
                throw PatternError("Claude stopped with an error: \(message)")
            default:
                break
            }
            return false
        }
    }

    static func decode(_ json: String) throws -> ImportDraft {
        guard var object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
            throw PatternError("Claude's reply wasn't a pattern draft.")
        }
        object["method"] = ImportDraft.Method.claude.rawValue
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(ImportDraft.self, from: data)
    }

    static func errorMessage(status: Int, body: String) -> String {
        let message = (try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
            .flatMap { ($0["error"] as? [String: Any])?["message"] as? String } ?? body
        switch status {
        case 401: return "The Anthropic API key wasn't accepted. Check it in Settings."
        case 429: return "Anthropic's API is busy or the account's limit was reached; try again in a minute. (\(message))"
        default: return "Anthropic's API returned \(status): \(message)"
        }
    }

    func body(pdf: Data) -> [String: Any] {
        [
            "model": Self.model,
            "max_tokens": 64000,
            "stream": true,
            "fallbacks": "default",
            "output_config": ["effort": "high", "format": ["type": "json_schema", "schema": Self.schema]],
            "system": Self.instructions,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "document", "source": ["type": "base64", "media_type": "application/pdf", "data": pdf.base64EncodedString()]],
                    ["type": "text", "text": "Read this knitting pattern into the draft format."],
                ],
            ]],
        ]
    }

    static let instructions = """
        You turn a knitting pattern PDF into a draft that a regrading app can use. The app regrades \
        each number that changes with size by interpolating between the designer's sizes, then fills \
        the numbers back into the instructions. A knitter checks your draft before it is saved.

        - sizes: the size names in order, as the pattern lists them.
        - gauge: per 10 cm (treat 4 in as 10 cm). stitchPattern and needle as written, or "".
        - chestEase: the recommended ease at the chest in cm (negative for negative ease), or null.
        - measurements: every finished measurement per size, in cm (convert inches), from the size \
          table or schematic. Set dimension to the matching garment measurement or null. Always \
          include the finished chest; if the pattern only gives the width across the back, double it \
          and say so in the label. ids are single lower-case letters, a, b, c…
        - numbers: every number in the instructions that differs between sizes, with one value per size. \
          kind: stitches, rows (rows or rounds), count (times to repeat), length (in cm), yarn (in metres) \
          or number. driver: the measurement it grows with (stitch counts around the body follow chest, \
          sleeve stitches follow upperArm, lengths worked to follow bodyLength, sleeveLength or yokeDepth), \
          or null for chest. ids are short and readable, like backCO or sleeveDecs; reuse one id when the \
          same quantity appears more than once. context: the sentence it comes from.
        - sections: the instructions in order, one line per step, exactly as the designer wrote them \
          except that each size-dependent number (with its "(…)" list) is replaced by {id}. Write \
          lengths as {id:len} and yarn amounts as {id:yarn}, removing the original unit text, since the \
          app prints both cm and inches. Keep units like "sts" and "rows" after {id}. Sub-headings are \
          lines starting with "## ". Set include to false for material that isn't instructions \
          (yarn, needles, abbreviations, techniques, designer notes); true for the knitting steps.
        - chartPages: 1-based page numbers of charts that the knitter needs (they're printed with the \
          regraded pattern), with a short title.
        - notes: anything the knitter must check: steps written for some sizes only, numbers you were \
          unsure of, charts that change with size. Keep each note to a sentence.
        - garment: cardigan, pullover, or null.
        Don't invent numbers. If something is unreadable, leave it out and add a note.
        """

    // MARK: Schema

    static var schema: [String: Any] {
        func nullable(_ s: [String: Any]) -> [String: Any] { ["anyOf": [s, ["type": "null"]]] }
        func object(_ props: [String: Any]) -> [String: Any] {
            ["type": "object", "properties": props, "required": Array(props.keys).sorted(), "additionalProperties": false]
        }
        let string: [String: Any] = ["type": "string"]
        let number: [String: Any] = ["type": "number"]
        let numbers: [String: Any] = ["type": "array", "items": number]
        let dimension: [String: Any] = ["type": "string", "enum": GarmentMeasure.allCases.map(\.rawValue)]
        let kind: [String: Any] = ["type": "string", "enum": ["stitches", "rows", "length", "count", "yarn", "number"]]
        return object([
            "name": string,
            "designer": string,
            "garment": nullable(["type": "string", "enum": ["pullover", "cardigan"]]),
            "sizes": ["type": "array", "items": string],
            "gauge": object(["stitchesPer10cm": number, "rowsPer10cm": number, "stitchPattern": string, "needle": string]),
            "chestEase": nullable(number),
            "measurements": ["type": "array", "items": object(["id": string, "label": string, "dimension": nullable(dimension), "values": numbers])],
            "numbers": ["type": "array", "items": object(["id": string, "kind": kind, "driver": nullable(dimension), "values": numbers, "context": string])],
            "sections": ["type": "array", "items": object(["id": string, "title": string, "lines": ["type": "array", "items": string], "include": ["type": "boolean"]])],
            "chartPages": ["type": "array", "items": object(["title": string, "page": ["type": "integer"]])],
            "notes": ["type": "array", "items": string],
        ])
    }
}
