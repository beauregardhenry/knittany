import Foundation

/// The small formula language used in pattern files, e.g.
/// `nearestMod(alineFront, 3, 1)` or `backCO - 2*underarmEvents`.
/// Values are numbers; comparisons and `&&`, `||`, `!` give 1 or 0.
public indirect enum Expr: Sendable, Equatable {
    case number(Double)
    case ident(String)
    case negate(Expr)
    case not(Expr)
    case binary(BinaryOp, Expr, Expr)
    case call(String, [Expr])

    public static func parse(_ text: String) throws -> Expr {
        var parser = try ExprParser(text)
        return try parser.parseAll()
    }

    public var identifiers: Set<String> {
        switch self {
        case .number: []
        case .ident(let name): [name]
        case .negate(let e), .not(let e): e.identifiers
        case .binary(_, let a, let b): a.identifiers.union(b.identifiers)
        case .call(_, let args): args.reduce(into: Set()) { $0.formUnion($1.identifiers) }
        }
    }
}

public enum BinaryOp: String, Sendable {
    case add = "+", sub = "-", mul = "*", div = "/", mod = "%"
    case eq = "==", ne = "!=", lt = "<", le = "<=", gt = ">", ge = ">="
    case and = "&&", or = "||"
}

public struct ExpressionError: Error, CustomStringConvertible, Equatable {
    public var description: String
    public init(_ description: String) { self.description = description }
}

/// What a formula can see: named values, and the knitter's gauge for the
/// `sts()`, `rows()` and `cm()` conversions.
public struct ExpressionScope {
    public var lookup: (String) throws -> Double
    public var gauge: Gauge

    public init(gauge: Gauge, lookup: @escaping (String) throws -> Double) {
        self.gauge = gauge
        self.lookup = lookup
    }
}

extension Expr {
    public func evaluate(in scope: ExpressionScope) throws -> Double {
        switch self {
        case .number(let v):
            return v
        case .ident(let name):
            return try scope.lookup(name)
        case .negate(let e):
            return -(try e.evaluate(in: scope))
        case .not(let e):
            return try e.evaluate(in: scope) == 0 ? 1 : 0
        case .binary(let op, let a, let b):
            let x = try a.evaluate(in: scope)
            if op == .and && x == 0 { return 0 }
            if op == .or && x != 0 { return 1 }
            let y = try b.evaluate(in: scope)
            switch op {
            case .add: return x + y
            case .sub: return x - y
            case .mul: return x * y
            case .div:
                guard y != 0 else { throw ExpressionError("division by zero") }
                return x / y
            case .mod:
                guard y != 0 else { throw ExpressionError("modulo by zero") }
                return Self.positiveMod(x, y)
            case .eq: return abs(x - y) < 1e-9 ? 1 : 0
            case .ne: return abs(x - y) < 1e-9 ? 0 : 1
            case .lt: return x < y ? 1 : 0
            case .le: return x <= y + 1e-9 ? 1 : 0
            case .gt: return x > y ? 1 : 0
            case .ge: return x + 1e-9 >= y ? 1 : 0
            case .and, .or: return y != 0 ? 1 : 0
            }
        case .call(let name, let args):
            return try Self.call(name, args, scope)
        }
    }

    static func positiveMod(_ x: Double, _ m: Double) -> Double {
        let r = x.truncatingRemainder(dividingBy: m)
        return r < 0 ? r + abs(m) : r
    }

    /// Rounds half up (2.5 → 3, -2.5 → -2), the way knitters round counts.
    public static func roundHalfUp(_ x: Double) -> Double {
        (x + 0.5).rounded(.down)
    }

    /// Nearest number that leaves `remainder` when divided by `multiple`; ties go up.
    public static func nearestMod(_ x: Double, _ multiple: Double, _ remainder: Double) -> Double {
        let below = x - positiveMod(x - remainder, multiple)
        let above = below + multiple
        return (x - below) < (above - x) - 1e-9 ? below : above
    }

    static func call(_ name: String, _ args: [Expr], _ scope: ExpressionScope) throws -> Double {
        func arity(_ n: Int) throws {
            guard args.count == n else { throw ExpressionError("\(name)() takes \(n) argument(s)") }
        }
        if name == "if" {
            try arity(3)
            return try args[0].evaluate(in: scope) != 0 ? args[1].evaluate(in: scope) : args[2].evaluate(in: scope)
        }
        let v = try args.map { try $0.evaluate(in: scope) }
        switch name {
        case "floor": try arity(1); return v[0].rounded(.down)
        case "ceil": try arity(1); return v[0].rounded(.up)
        case "round": try arity(1); return roundHalfUp(v[0])
        case "abs": try arity(1); return abs(v[0])
        case "min":
            guard let m = v.min() else { throw ExpressionError("min() needs arguments") }
            return m
        case "max":
            guard let m = v.max() else { throw ExpressionError("max() needs arguments") }
            return m
        case "clamp": try arity(3); return Swift.min(Swift.max(v[0], v[1]), v[2])
        case "nearestMod":
            try arity(3)
            guard v[1] > 0 else { throw ExpressionError("nearestMod() needs a positive multiple") }
            return nearestMod(v[0], v[1], v[2])
        case "roundTo":
            try arity(2)
            guard v[1] > 0 else { throw ExpressionError("roundTo() needs a positive step") }
            return roundHalfUp(v[0] / v[1]) * v[1]
        case "sts": try arity(1); return v[0] * scope.gauge.stitchesPerCm
        case "rows": try arity(1); return v[0] * scope.gauge.rowsPerCm
        case "cm": try arity(1); return v[0] / scope.gauge.stitchesPerCm
        case "cmRows": try arity(1); return v[0] / scope.gauge.rowsPerCm
        default: throw ExpressionError("unknown function \(name)()")
        }
    }
}

private enum Token: Equatable {
    case number(Double)
    case ident(String)
    case op(String)
    case lparen, rparen, comma
}

private struct ExprParser {
    let text: String
    var tokens: [Token] = []
    var pos = 0

    init(_ text: String) throws {
        self.text = text
        tokens = try Self.lex(text)
    }

    static func lex(_ text: String) throws -> [Token] {
        let chars = Array(text)
        var out: [Token] = []
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            if c.isNumber || (c == "." && i + 1 < chars.count && chars[i + 1].isNumber) {
                var j = i
                while j < chars.count, chars[j].isNumber || chars[j] == "." { j += 1 }
                guard let v = Double(String(chars[i..<j])) else { throw ExpressionError("bad number in \(text)") }
                out.append(.number(v))
                i = j
                continue
            }
            if c.isLetter || c == "_" {
                var j = i
                while j < chars.count, chars[j].isLetter || chars[j].isNumber || chars[j] == "_" { j += 1 }
                out.append(.ident(String(chars[i..<j])))
                i = j
                continue
            }
            if i + 1 < chars.count {
                let two = String(chars[i...i + 1])
                if ["==", "!=", "<=", ">=", "&&", "||"].contains(two) {
                    out.append(.op(two))
                    i += 2
                    continue
                }
            }
            switch c {
            case "(": out.append(.lparen)
            case ")": out.append(.rparen)
            case ",": out.append(.comma)
            case "+", "-", "*", "/", "%", "<", ">", "!": out.append(.op(String(c)))
            default: throw ExpressionError("unexpected '\(c)' in \(text)")
            }
            i += 1
        }
        return out
    }

    var peek: Token? { pos < tokens.count ? tokens[pos] : nil }

    mutating func next() -> Token? {
        defer { pos += 1 }
        return peek
    }

    mutating func accept(_ op: String) -> Bool {
        if peek == .op(op) { pos += 1; return true }
        return false
    }

    mutating func parseAll() throws -> Expr {
        let e = try parseOr()
        guard peek == nil else { throw ExpressionError("unexpected text after formula: \(text)") }
        return e
    }

    mutating func parseOr() throws -> Expr {
        var e = try parseAnd()
        while accept("||") { e = .binary(.or, e, try parseAnd()) }
        return e
    }

    mutating func parseAnd() throws -> Expr {
        var e = try parseNot()
        while accept("&&") { e = .binary(.and, e, try parseNot()) }
        return e
    }

    mutating func parseNot() throws -> Expr {
        if accept("!") { return .not(try parseNot()) }
        return try parseComparison()
    }

    mutating func parseComparison() throws -> Expr {
        let e = try parseAdd()
        for op in [BinaryOp.eq, .ne, .le, .ge, .lt, .gt] where accept(op.rawValue) {
            return .binary(op, e, try parseAdd())
        }
        return e
    }

    mutating func parseAdd() throws -> Expr {
        var e = try parseMul()
        while true {
            if accept("+") { e = .binary(.add, e, try parseMul()) }
            else if accept("-") { e = .binary(.sub, e, try parseMul()) }
            else { return e }
        }
    }

    mutating func parseMul() throws -> Expr {
        var e = try parseUnary()
        while true {
            if accept("*") { e = .binary(.mul, e, try parseUnary()) }
            else if accept("/") { e = .binary(.div, e, try parseUnary()) }
            else if accept("%") { e = .binary(.mod, e, try parseUnary()) }
            else { return e }
        }
    }

    mutating func parseUnary() throws -> Expr {
        if accept("-") { return .negate(try parseUnary()) }
        if accept("!") { return .not(try parseUnary()) }
        return try parsePrimary()
    }

    mutating func parsePrimary() throws -> Expr {
        switch next() {
        case .number(let v):
            return .number(v)
        case .ident(let name):
            guard peek == .lparen else { return .ident(name) }
            pos += 1
            var args: [Expr] = []
            if peek != .rparen {
                args.append(try parseOr())
                while peek == .comma {
                    pos += 1
                    args.append(try parseOr())
                }
            }
            guard next() == .rparen else { throw ExpressionError("missing ')' in \(text)") }
            return .call(name, args)
        case .lparen:
            let e = try parseOr()
            guard next() == .rparen else { throw ExpressionError("missing ')' in \(text)") }
            return e
        default:
            throw ExpressionError("incomplete formula: \(text)")
        }
    }
}
