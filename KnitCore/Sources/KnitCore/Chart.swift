import Foundation

/// A knitting chart as a grid of symbol keys. Row 1 is the bottom row.
public struct Chart: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    /// Rows from the bottom (row 1) up; each row lists cells right to left as
    /// knitters read a right-side row, so `rows[0][0]` is the bottom-right cell.
    public var rows: [[String]]
    public var legend: [ChartSymbol]
    public var inTheRound: Bool?
    public var when: String?

    public var width: Int { rows.map(\.count).max() ?? 0 }
    public var height: Int { rows.count }

    public func validate() throws {
        guard !rows.isEmpty, rows.allSatisfy({ $0.count == width }) else {
            throw PatternError("chart \(id) needs rows of equal width")
        }
        let keys = Set(legend.map(\.key))
        for (r, row) in rows.enumerated() {
            for key in row where !keys.contains(key) {
                throw PatternError("chart \(id) row \(r + 1) uses '\(key)', which isn't in its legend")
            }
        }
    }
}

public struct ChartSymbol: Codable, Sendable, Equatable {
    public enum Mark: String, Codable, Sendable {
        case blank, circle, cross, dot, slash, backslash, dash, filled
    }

    public var key: String
    public var label: String
    public var mark: Mark
    /// Cell colour as hex, e.g. "#C8102E"; nil for white.
    public var color: String?
}

/// A page of the original PDF to include with the regraded pattern, e.g. a
/// chart that doesn't change with size.
public struct SourcePage: Codable, Sendable, Equatable {
    public var title: String
    /// 1-based page number in the original PDF.
    public var page: Int
    public var when: String?

    public init(title: String, page: Int, when: String? = nil) {
        self.title = title
        self.page = page
        self.when = when
    }
}
