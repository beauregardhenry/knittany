import AppKit
import KnitCore

/// A front-view schematic of a top-down sweater, drawn to the regraded
/// proportions and labelled with the pattern's measurement letters.
public struct SchematicDrawing {
    public struct Label {
        public var letter: String
        public var text: String
    }

    let labels: [GarmentMeasure: Label]
    let size: [GarmentMeasure: Double]
    let garment: GarmentType
    let shape: SleeveShape
    let neckline: Neckline

    public init(result: GradeResult) {
        var labels: [GarmentMeasure: Label] = [:]
        var size: [GarmentMeasure: Double] = [:]
        for s in result.schematic where labels[s.entry.dimension] == nil {
            labels[s.entry.dimension] = Label(letter: s.entry.id.prefix(1).description, text: result.formatter.length(s.target))
            size[s.entry.dimension] = s.target
        }
        self.labels = labels
        self.size = size
        self.garment = result.pattern.garment ?? .pullover
        self.shape = result.pattern.shape ?? .setIn
        self.neckline = result.pattern.neckline ?? .round
    }

    struct Geometry {
        var body: [CGPoint]
        var leftSleeve: [CGPoint]
        var rightSleeve: [CGPoint]
        var neck: [CGPoint]
        var centreFront: (CGPoint, CGPoint)?
        /// Construction lines drawn over the outline: the edge of a round yoke and its ribs.
        var details: [[CGPoint]]
        var annotations: [Annotation]
        var bounds: CGRect
    }

    struct Annotation {
        var dimension: GarmentMeasure
        var from: CGPoint
        var to: CGPoint
        var label: CGPoint
        var anchor: Ink.Anchor

        init(_ dimension: GarmentMeasure, _ from: CGPoint, _ to: CGPoint, _ label: CGPoint, _ anchor: Ink.Anchor) {
            self.dimension = dimension
            self.from = from
            self.to = to
            self.label = label
            self.anchor = anchor
        }
    }

    /// The outline in cm, origin at the centre of the back neck, y down.
    func geometry() -> Geometry {
        let chest = size[.chest] ?? 100
        let w = chest / 2
        let h = (size[.hem] ?? chest) / 2
        let yoke = size[.yokeDepth] ?? w * 0.4
        let length = size[.bodyLength] ?? w * 0.8
        let upperArm = (size[.upperArm] ?? chest * 0.3) / 2
        let cuff = (size[.cuff] ?? upperArm * 1.4) / 2
        let sleeve = size[.sleeveLength] ?? 44
        // A neck opening is drawn about a third as wide as it is round.
        let neckHalf = (size[.neckWidth] ?? size[.neckOpening].map { $0 / 3 } ?? w * 0.36) / 2
        let shoulderDrop = yoke * 0.14

        let shoulderL = CGPoint(x: -w / 2, y: shoulderDrop)
        let underarmL = CGPoint(x: -w / 2, y: yoke)
        let hemL = CGPoint(x: -h / 2, y: yoke + length)
        func mirror(_ p: CGPoint) -> CGPoint { CGPoint(x: -p.x, y: p.y) }

        let neckL = CGPoint(x: -neckHalf, y: 0)
        // Raglans and yokes have no shoulder line: the sleeve runs up to the neck.
        let seamless = shape != .setIn
        let body = seamless
            ? [neckL, underarmL, hemL, mirror(hemL), mirror(underarmL), mirror(neckL)]
            : [neckL, shoulderL, underarmL, hemL, mirror(hemL), mirror(underarmL), mirror(shoulderL), mirror(neckL)]

        // Sleeve: hangs from the armhole at the angle that gives its upper-arm width.
        let armhole = underarmL.y - shoulderL.y
        // A vertical armhole of height h gives a sleeve h·cos(angle) wide.
        let cosA = min(0.95, max(0.35, upperArm / max(armhole, 1)))
        let angle = acos(cosA)
        let dir = CGPoint(x: -cos(angle), y: sin(angle))
        let normal = CGPoint(x: -dir.y, y: dir.x)
        let mid = CGPoint(x: shoulderL.x, y: (shoulderL.y + underarmL.y) / 2)
        let end = CGPoint(x: mid.x + dir.x * sleeve, y: mid.y + dir.y * sleeve)
        let endA = CGPoint(x: end.x + normal.x * cuff / 2, y: end.y + normal.y * cuff / 2)
        let endB = CGPoint(x: end.x - normal.x * cuff / 2, y: end.y - normal.y * cuff / 2)
        let (cuffTop, cuffBottom) = endA.y < endB.y ? (endA, endB) : (endB, endA)
        let leftSleeve = [seamless ? neckL : shoulderL, cuffTop, cuffBottom, underarmL]
        let rightSleeve = leftSleeve.map(mirror)

        let neckDepth: Double = switch (neckline, garment) {
        case (.v, .cardigan): yoke * 0.95
        case (.v, .pullover): yoke * 0.55
        case (.round, _): yoke * 0.3
        }
        let neck = neckline == .v
            ? [neckL, CGPoint(x: 0, y: neckDepth), mirror(neckL)]
            : [neckL, CGPoint(x: -neckHalf * 0.6, y: neckDepth * 0.8), CGPoint(x: 0, y: neckDepth),
               CGPoint(x: neckHalf * 0.6, y: neckDepth * 0.8), mirror(neckL)]
        let centreFront = garment == .cardigan ? (CGPoint(x: 0, y: neckDepth), CGPoint(x: 0, y: yoke + length)) : nil

        // A round yoke: its lower edge dips a little at the centre, with ribs fanning out from the neck.
        var details: [[CGPoint]] = []
        if shape == .yoke {
            let control = CGPoint(x: 0, y: yoke * 1.2)
            func edge(_ t: Double) -> CGPoint {
                let a = underarmL, c = mirror(underarmL), u = 1 - t
                return CGPoint(x: u * u * a.x + 2 * u * t * control.x + t * t * c.x, y: u * u * a.y + 2 * u * t * control.y + t * t * c.y)
            }
            details.append(stride(from: 0.0, through: 1, by: 0.05).map(edge))
            func neckPoint(_ t: Double) -> CGPoint {
                let x = -neckHalf + 2 * neckHalf * t
                let depth = neckline == .v ? neckDepth * (1 - abs(x) / neckHalf) : neckDepth * (1 - pow(x / neckHalf, 2))
                return CGPoint(x: x, y: depth)
            }
            for k in 1...13 {
                let t = Double(k) / 14
                details.append([neckPoint(t), edge(t)])
            }
        }

        func add(_ a: CGPoint, _ b: CGPoint, _ k: CGFloat) -> CGPoint { CGPoint(x: a.x + b.x * k, y: a.y + b.y * k) }
        let shapes = body + leftSleeve + rightSleeve
        let shapeMinX = shapes.map(\.x).min()!
        let dimX = shapeMinX - 3

        // `normal` points up and away from the body on the left sleeve.
        let upL = normal
        let dirR = CGPoint(x: -dir.x, y: dir.y)
        let upR = CGPoint(x: -upL.x, y: upL.y)
        let midR = mirror(mid), endR = mirror(end)
        let armCentre = add(midR, dirR, 5)
        let gFrom = add(mid, upL, upperArm / 2 + 2.5), gTo = add(end, upL, cuff / 2 + 2.5)

        let notes: [Annotation] = [
            Annotation(.yokeDepth, CGPoint(x: dimX, y: shape == .setIn ? shoulderDrop : 0), CGPoint(x: dimX, y: yoke),
                       CGPoint(x: dimX - 1.5, y: yoke / 2), .right),
            Annotation(.bodyLength, CGPoint(x: dimX, y: yoke), CGPoint(x: dimX, y: yoke + length),
                       CGPoint(x: dimX - 1.5, y: yoke + length * 0.65), .right),
            Annotation(.chest, CGPoint(x: -w / 2, y: yoke + 3), CGPoint(x: w / 2, y: yoke + 3), CGPoint(x: 0, y: yoke + 5.5), .center),
            Annotation(.hem, CGPoint(x: -h / 2, y: yoke + length + 4), CGPoint(x: h / 2, y: yoke + length + 4),
                       CGPoint(x: 0, y: yoke + length + 6.5), .center),
            Annotation(.upperArm, add(armCentre, upR, upperArm / 2), add(armCentre, upR, -upperArm / 2),
                       add(add(armCentre, upR, upperArm / 2), upR, 2), .left),
            Annotation(.cuff, mirror(endA), mirror(endB), add(endR, dirR, 3), .left),
            Annotation(.sleeveLength, gFrom, gTo, add(CGPoint(x: (gFrom.x + gTo.x) / 2, y: (gFrom.y + gTo.y) / 2), upL, 4), .center),
        ]

        let xs = shapes.map(\.x) + notes.flatMap { [$0.from.x, $0.to.x, $0.label.x] }
        let ys = shapes.map(\.y) + notes.flatMap { [$0.from.y, $0.to.y, $0.label.y] }
        // Room for label text: about 16 cm either side at typical scales.
        let bounds = CGRect(x: xs.min()! - 18, y: ys.min()! - 3, width: xs.max()! - xs.min()! + 36, height: ys.max()! - ys.min()! + 6)
        return Geometry(
            body: body, leftSleeve: leftSleeve, rightSleeve: rightSleeve, neck: neck,
            centreFront: centreFront, details: details, annotations: notes, bounds: bounds
        )
    }

    /// Draws into `rect` of a y-down context.
    public func draw(in ctx: CGContext, rect: CGRect) {
        let g = geometry()
        let scale = min(rect.width / g.bounds.width, rect.height / g.bounds.height)
        let ox = rect.midX - g.bounds.midX * scale
        let oy = rect.midY - g.bounds.midY * scale
        func p(_ q: CGPoint) -> CGPoint { CGPoint(x: ox + q.x * scale, y: oy + q.y * scale) }

        func polygon(_ pts: [CGPoint]) {
            ctx.beginPath()
            ctx.addLines(between: pts.map(p))
            ctx.closePath()
            ctx.setFillColor(Ink.fill)
            ctx.setStrokeColor(Ink.line)
            ctx.setLineWidth(1.2)
            ctx.drawPath(using: .fillStroke)
        }
        polygon(g.leftSleeve)
        polygon(g.rightSleeve)
        polygon(g.body)

        ctx.setStrokeColor(Ink.line)
        ctx.setLineWidth(1)
        ctx.beginPath()
        ctx.addLines(between: g.neck.map(p))
        ctx.strokePath()
        ctx.saveGState()
        ctx.setStrokeColor(Ink.line)
        ctx.setLineWidth(0.6)
        for d in g.details {
            ctx.beginPath()
            ctx.addLines(between: d.map(p))
            ctx.strokePath()
        }
        ctx.restoreGState()
        if let (a, b) = g.centreFront {
            ctx.beginPath()
            ctx.move(to: p(a))
            ctx.addLine(to: p(b))
            ctx.strokePath()
        }

        for note in g.annotations {
            guard let label = labels[note.dimension] else { continue }
            let a = p(note.from), b = p(note.to)
            ctx.saveGState()
            ctx.setStrokeColor(Ink.accent)
            ctx.setLineWidth(0.8)
            ctx.setLineDash(phase: 0, lengths: [3, 2])
            ctx.beginPath()
            ctx.move(to: a)
            ctx.addLine(to: b)
            ctx.strokePath()
            ctx.restoreGState()
            ctx.setFillColor(Ink.accent)
            for end in [a, b] {
                ctx.fillEllipse(in: CGRect(x: end.x - 1.8, y: end.y - 1.8, width: 3.6, height: 3.6))
            }
            Ink.text("\(label.letter)  \(label.text)", at: p(note.label), in: ctx, size: 9, color: Ink.accent, anchor: note.anchor)
        }
    }
}
