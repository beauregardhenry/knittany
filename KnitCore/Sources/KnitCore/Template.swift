import Foundation

/// Renders one instruction line. `{expr}` or `{expr:format}` is replaced with a
/// value; `{if c}…{elif c}…{else}…{end}` keeps only the matching text.
public enum Template {
    public static let formats: Set<String> = ["len", "ordinal", "int", "yarn", "num"]

    public struct Hooks {
        public var value: (_ expression: String, _ format: String?) throws -> String
        public var condition: (_ expression: String) throws -> Bool

        public init(
            value: @escaping (String, String?) throws -> String,
            condition: @escaping (String) throws -> Bool
        ) {
            self.value = value
            self.condition = condition
        }
    }

    private struct Frame {
        var parentActive: Bool
        var taken: Bool
        var active: Bool
    }

    public static func render(_ line: String, hooks: Hooks) throws -> String {
        var out = ""
        var stack: [Frame] = []
        var active: Bool { stack.last?.active ?? true }
        var rest = Substring(line)

        while let open = rest.firstIndex(of: "{") {
            if active { out += rest[..<open] }
            guard let close = rest[open...].firstIndex(of: "}") else {
                throw ExpressionError("unclosed '{' in: \(line)")
            }
            let tag = rest[rest.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
            rest = rest[rest.index(after: close)...]

            if tag.hasPrefix("if ") {
                let parent = active
                let taken = parent ? try hooks.condition(String(tag.dropFirst(3))) : false
                stack.append(Frame(parentActive: parent, taken: taken, active: taken))
            } else if tag.hasPrefix("elif ") {
                guard var frame = stack.popLast() else { throw ExpressionError("{elif} without {if} in: \(line)") }
                if frame.parentActive && !frame.taken {
                    frame.active = try hooks.condition(String(tag.dropFirst(5)))
                    frame.taken = frame.active
                } else {
                    frame.active = false
                }
                stack.append(frame)
            } else if tag == "else" {
                guard var frame = stack.popLast() else { throw ExpressionError("{else} without {if} in: \(line)") }
                frame.active = frame.parentActive && !frame.taken
                frame.taken = true
                stack.append(frame)
            } else if tag == "end" {
                guard stack.popLast() != nil else { throw ExpressionError("{end} without {if} in: \(line)") }
            } else if active {
                var expression = tag
                var format: String?
                if let colon = tag.lastIndex(of: ":"), formats.contains(String(tag[tag.index(after: colon)...])) {
                    expression = String(tag[..<colon])
                    format = String(tag[tag.index(after: colon)...])
                }
                out += try hooks.value(expression, format)
            }
        }
        guard stack.isEmpty else { throw ExpressionError("{if} without {end} in: \(line)") }
        if active { out += rest }
        return out
    }
}
