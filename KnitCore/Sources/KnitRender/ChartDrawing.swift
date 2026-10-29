import AppKit
import KnitCore

/// Draws a chart grid with row and stitch numbers and a legend.
public struct ChartDrawing {
    public let chart: Chart
    public var maxCell: CGFloat = 14

    public init(chart: Chart) {
        self.chart = chart
    }

    /// The size the chart needs at a given cell size.
    public func size(cell: CGFloat) -> CGSize {
        CGSize(width: CGFloat(chart.width) * cell + 60, height: CGFloat(chart.height) * cell + 40 + legendHeight)
    }

    var legendHeight: CGFloat { CGFloat(chart.legend.count) * 14 + 8 }

    public func cellSize(fitting rect: CGRect) -> CGFloat {
        let w = (rect.width - 60) / CGFloat(max(chart.width, 1))
        let h = (rect.height - 40 - legendHeight) / CGFloat(max(chart.height, 1))
        return max(3, min(maxCell, w, h))
    }

    /// Draws into `rect` of a y-down context.
    public func draw(in ctx: CGContext, rect: CGRect) {
        let cell = cellSize(fitting: rect)
        let gridW = CGFloat(chart.width) * cell
        let gridH = CGFloat(chart.height) * cell
        let left = rect.minX + 26
        let top = rect.minY + 4
        let symbols = Dictionary(chart.legend.map { ($0.key, $0) }) { a, _ in a }
        let numberSize = min(8, max(5, cell * 0.6))

        for (r, row) in chart.rows.enumerated() {
            // Row 1 is at the bottom; cell 0 is the rightmost.
            let y = top + gridH - CGFloat(r + 1) * cell
            for (c, key) in row.enumerated() {
                let x = left + gridW - CGFloat(c + 1) * cell
                let box = CGRect(x: x, y: y, width: cell, height: cell)
                if let symbol = symbols[key] { drawMark(symbol, in: box, ctx: ctx) }
            }
            let rowNumber = r + 1
            let flat = chart.inTheRound != true
            let onLeft = flat && rowNumber % 2 == 0
            if cell >= 6 || rowNumber % 5 == 0 {
                Ink.text(
                    "\(rowNumber)",
                    at: CGPoint(x: onLeft ? left - 4 : left + gridW + 4, y: y + cell / 2),
                    in: ctx, size: numberSize, color: Ink.faint, anchor: onLeft ? .right : .left
                )
            }
        }

        ctx.setStrokeColor(Ink.grid)
        ctx.setLineWidth(0.5)
        for i in 0...chart.width {
            let x = left + CGFloat(i) * cell
            ctx.move(to: CGPoint(x: x, y: top))
            ctx.addLine(to: CGPoint(x: x, y: top + gridH))
        }
        for j in 0...chart.height {
            let y = top + CGFloat(j) * cell
            ctx.move(to: CGPoint(x: left, y: y))
            ctx.addLine(to: CGPoint(x: left + gridW, y: y))
        }
        ctx.strokePath()

        for c in 0..<chart.width where cell >= 8 || (c + 1) % 5 == 0 {
            Ink.text(
                "\(c + 1)", at: CGPoint(x: left + gridW - (CGFloat(c) + 0.5) * cell, y: top + gridH + 8),
                in: ctx, size: numberSize, color: Ink.faint
            )
        }

        var ly = top + gridH + 26
        for symbol in chart.legend {
            drawMark(symbol, in: CGRect(x: left, y: ly - 5, width: 10, height: 10), ctx: ctx)
            ctx.setStrokeColor(Ink.grid)
            ctx.stroke(CGRect(x: left, y: ly - 5, width: 10, height: 10))
            Ink.text(symbol.label, at: CGPoint(x: left + 16, y: ly), in: ctx, size: 8.5, anchor: .left)
            ly += 14
        }
    }

    func drawMark(_ symbol: ChartSymbol, in box: CGRect, ctx: CGContext) {
        if let fill = Ink.color(hex: symbol.color) {
            ctx.setFillColor(fill)
            ctx.fill(box)
        }
        let inset = box.insetBy(dx: box.width * 0.22, dy: box.height * 0.22)
        ctx.setStrokeColor(Ink.line)
        ctx.setFillColor(Ink.line)
        ctx.setLineWidth(max(0.6, box.width * 0.08))
        switch symbol.mark {
        case .blank:
            break
        case .circle:
            ctx.strokeEllipse(in: inset)
        case .dot:
            ctx.fillEllipse(in: box.insetBy(dx: box.width * 0.36, dy: box.height * 0.36))
        case .cross:
            ctx.move(to: CGPoint(x: inset.minX, y: inset.minY))
            ctx.addLine(to: CGPoint(x: inset.maxX, y: inset.maxY))
            ctx.move(to: CGPoint(x: inset.maxX, y: inset.minY))
            ctx.addLine(to: CGPoint(x: inset.minX, y: inset.maxY))
            ctx.strokePath()
        case .slash:
            ctx.move(to: CGPoint(x: inset.minX, y: inset.maxY))
            ctx.addLine(to: CGPoint(x: inset.maxX, y: inset.minY))
            ctx.strokePath()
        case .backslash:
            ctx.move(to: CGPoint(x: inset.minX, y: inset.minY))
            ctx.addLine(to: CGPoint(x: inset.maxX, y: inset.maxY))
            ctx.strokePath()
        case .dash:
            ctx.move(to: CGPoint(x: inset.minX, y: box.midY))
            ctx.addLine(to: CGPoint(x: inset.maxX, y: box.midY))
            ctx.strokePath()
        case .filled:
            ctx.setFillColor(Ink.line)
            ctx.fill(box)
        }
    }
}
