import Foundation

/// Writes a top-down sweater pattern from the knitter's design choices. The
/// result is an ordinary parametric pattern, drawn for every standard size:
/// every count is a formula over the finished measurements and the gauge, so
/// it regrades to any person like an imported pattern does.
public enum Designer {
    public static func pattern(from c: DesignChoices) throws -> Pattern {
        var w = Writer(c)
        w.common()
        switch c.construction {
        case .raglan: w.raglanYoke()
        case .yoke: w.roundYoke()
        }
        w.body()
        w.sleeves()
        if c.garment == .cardigan { w.bands() }
        w.finishing()

        let sizing = DesignSizing.rows(for: c)
        let pattern = Pattern(
            name: c.name.isEmpty ? c.defaultName : c.name,
            designer: nil,
            source: "Designed in the app",
            construction: w.construction,
            garment: c.garment,
            shape: c.construction == .raglan ? .raglan : .yoke,
            neckline: .round,
            sizes: c.sizeChart.sizes,
            gauge: c.gauge,
            primaryDimension: .chest,
            statedEase: DesignSizing.statedEase(for: c),
            schematic: sizing.map { SchematicEntry(id: $0.id, label: $0.label, dimension: $0.dimension, values: $0.values, achieved: w.achieved[$0.id]) },
            quantities: w.quantities,
            checks: w.checks,
            sections: w.sections
        )
        var designed = pattern
        designed.design = c
        designed.sizedFor = c.sizeChart
        try designed.validate()
        return designed
    }
}

/// Builds the quantities and instruction text. Flat pieces (cardigans) say
/// rows and RS/WS; pullovers are worked in the round.
struct Writer {
    let c: DesignChoices
    let flat: Bool
    var quantities: [Quantity] = []
    var sections: [Section] = []
    var checks: [PatternCheck] = []
    var achieved: [String: String] = [:]
    var construction = ""

    init(_ c: DesignChoices) {
        self.c = c
        flat = c.garment == .cardigan
    }

    var round: String { flat ? "row" : "round" }
    var rounds: String { flat ? "rows" : "rounds" }

    mutating func q(_ id: String, _ kind: QuantityKind, _ formula: String, internal hidden: Bool = false) {
        quantities.append(Quantity(id: id, kind: kind, formula: formula, internal: hidden ? true : nil))
    }

    mutating func value(_ id: String, _ kind: QuantityKind, _ v: Double) {
        quantities.append(Quantity(id: id, kind: kind, value: v, internal: true))
    }

    mutating func section(_ title: String, _ lines: [String]) {
        sections.append(Section(title: title, lines: lines.filter { !$0.isEmpty }))
    }

    // MARK: Finishes

    /// Stitch multiple and remainder a finish needs: flat ribs are balanced, with a knit stitch at each edge.
    func multiple(_ f: DesignChoices.Finish, flat: Bool) -> (Int, Int) {
        switch f {
        case .rib1x1: flat ? (2, 1) : (2, 0)
        case .rib2x2: flat ? (4, 2) : (4, 0)
        case .garter, .rolled: (1, 0)
        }
    }

    func describe(_ f: DesignChoices.Finish, flat: Bool) -> String {
        switch (f, flat) {
        case (.rib1x1, false): "1x1 rib: (k1, p1) around"
        case (.rib2x2, false): "2x2 rib: (k2, p2) around"
        case (.garter, false): "garter stitch: purl 1 round, knit 1 round"
        case (.rolled, false): "stockinette (knit every round), letting the edge roll"
        case (.rib1x1, true): "1x1 rib: k1, (p1, k1) to end on RS rows; p1, (k1, p1) to end on WS rows"
        case (.rib2x2, true): "2x2 rib: k2, (p2, k2) to end on RS rows; p2, (k2, p2) to end on WS rows"
        case (.garter, true): "garter stitch: knit every row"
        case (.rolled, true): "stockinette, letting the edge roll"
        }
    }

    /// An evenly-spaced adjustment so `count` fits the finish: "(decreasing 2 sts evenly in the first round)".
    func adjustText(_ id: String) -> String {
        "{if \(id) > 0} Decrease {\(id)Abs} sts evenly across the first \(round).{elif \(id) < 0} Increase {\(id)Abs} sts evenly across the first \(round).{end}"
    }

    mutating func adjustment(_ id: String, from count: String, finish f: DesignChoices.Finish, flat isFlat: Bool) {
        let (m, r) = multiple(f, flat: isFlat)
        q(id + "Count", .stitches, "nearestMod(\(count), \(m), \(r))")
        q(id, .stitches, "\(count) - \(id)Count")
        q(id + "Abs", .stitches, "abs(\(id))")
    }

    // MARK: Shared numbers

    mutating func common() {
        // Body and sleeve targets at the knitter's gauge.
        q("bodyT", .number, "sts(target_a)", internal: true)
        q("armT", .number, "sts(target_b)", internal: true)
        q("u", .stitches, "max(2, 2 * round(sts(target_a) * 0.025))")
        let (m, r) = multiple(c.neckband, flat: flat)
        let neckMultiple = max(m, 4)
        q("co", .stitches, flat
            ? "max(40, nearestMod(sts(target_h), \(neckMultiple), \(m == 1 ? 0 : r)))"
            : "max(40, nearestMod(sts(target_h), 4, 0))")
        value("neckCm", .length, DesignSizing.neckbandDepth(c.neckband))
        q("neckRows", .rows, "max(4, 2 * round(rows(neckCm) / 2))")
        q("D", .rows, "max(8, 2 * round(rows(target_c) / 2) - neckRows)", internal: true)
        checks.append(PatternCheck(expr: "D >= 8", message: "The yoke is very shallow; check the yoke depth.", when: nil))
    }

    var castOnLines: [String] {
        var lines = [
            flat
                ? "Cast on {co} sts. Don't join; the cardigan is worked back and forth."
                : "Cast on {co} sts. Join to work in the round, being careful not to twist, and place a marker for the beginning of the round.",
            "Neckband: work \(describe(c.neckband, flat: flat)) for {neckCm:len} ({neckRows} \(rounds)).",
        ]
        if c.stripes {
            lines.append("Stripes: from here on, change colour every 4 \(rounds) (Colour A, then Colour B), carrying the colour not in use up the inside.")
        }
        return lines
    }

    // MARK: Raglan

    mutating func raglanYoke() {
        construction = "Top-down raglan \(flat ? "cardigan, worked flat with picked-up bands" : "pullover, worked in the round"), with the sleeves and body joined along four raglan lines"
        q("s0", .stitches, "max(4, 2 * round(co / 12))")
        if flat {
            q("fh", .stitches, "round((co - 2 * s0) / 4)")
            q("b0", .stitches, "co - 2 * s0 - 2 * fh")
            q("f0", .stitches, "2 * fh")
        } else {
            q("b0", .stitches, "(co - 2 * s0) / 2")
            q("f0", .stitches, "co - 2 * s0 - b0")
        }
        // Each full increase adds 2 sts to each piece (1 to each cardigan front); see the raglan notes in the README.
        q("evBody", .number, "(bodyT - f0 - b0 - 2 * u) / 4", internal: true)
        q("evArm", .number, "(armT - s0 - u) / 2", internal: true)
        q("F", .count, "max(1, round(min(evBody, evArm)))")
        q("Xb", .count, "max(0, floor(evBody - F + 0.25))")
        q("Xs", .count, "max(0, floor(evArm - F + 0.25))")
        q("X", .count, "Xb + Xs")
        // Full raglan increases go on every other round (every RS row); if they don't fit,
        // the last ones go on every round. Body-only or sleeve-only increases use the rounds in between.
        q("wF", .count, "max(0, F - D / 2)")
        q("lastFull", .rows, "2 * F - 1")
        q("rapidStart", .rows, "D - 2 * wF + 1")
        q("oddEnd", .rows, "rapidStart - 2")
        q("partialEnd", .rows, "2 * X")
        q("afterYoke", .stitches, "co + 8 * F + 4 * X")
        q("frontY", .stitches, "f0 + 2 * (F + Xb)")
        q("fhY", .stitches, "frontY / 2")
        q("backY", .stitches, "b0 + 2 * (F + Xb)")
        q("sleeveY", .stitches, "s0 + 2 * (F + Xs)")
        q("body", .stitches, "frontY + backY + 2 * u")
        q("halfU", .stitches, "u / 2")
        q("sleeve", .stitches, "sleeveY + u")
        checks.append(PatternCheck(expr: "afterYoke == frontY + backY + 2 * sleeveY", message: "Internal: the yoke count {afterYoke} doesn't add up.", when: nil))
        checks.append(PatternCheck(expr: "X <= (D - 2 * wF) / 2", message: "The yoke is too shallow for this many increases; make it deeper or the fit closer.", when: nil))
        achieved["a"] = "cm(body)"
        achieved["b"] = "cm(sleeve)"

        let inc = "*Knit to 1 st before the marker, M1R, k1, slip marker, k1, M1L; repeat from * 3 more times, knit to the end"
        let incWS = "*Purl to 1 st before the marker, M1LP, p1, slip marker, p1, M1RP; repeat from * 3 more times, purl to the end"
        let bodyInc = "K1, M1L, knit to 1 st before the marker, M1R, k1, slip marker (back); knit to the marker, slip marker (sleeve); k1, M1L, knit to 1 st before the marker, M1R, k1, slip marker (front); knit to the end (sleeve)"
        let sleeveInc = "Knit to the marker, slip marker (back); k1, M1L, knit to 1 st before the marker, M1R, k1, slip marker (sleeve); knit to the marker, slip marker (front); k1, M1L, knit to 1 st before the end, M1R, k1 (sleeve)"
        let bodyIncWS = "Purl to 1 st before the 1st marker, M1RP, p1, slip marker, purl to the 2nd marker, slip marker, p1, M1LP, purl to 1 st before the 3rd marker, M1RP, p1, slip marker, purl to the 4th marker, slip marker, p1, M1LP, purl to the end"
        let sleeveIncWS = "Purl to the 1st marker, slip marker, p1, M1LP, purl to 1 st before the 2nd marker, M1RP, p1, slip marker, purl to the 3rd marker, slip marker, p1, M1LP, purl to 1 st before the 4th marker, M1RP, p1, slip marker, purl to the end"
        let R = round.capitalized
        let odd = flat ? "RS row" : "odd round"
        let even = flat ? "WS row" : "even round"

        var lines = castOnLines
        lines += flat
            ? ["Set-up row (RS): K{fh} (right front), pm, k{s0} (sleeve), pm, k{b0} (back), pm, k{s0} (sleeve), pm, k{fh} (left front).",
               "Next row (WS): Purl. The yoke rows below are counted from the next row, Row 1 (RS)."]
            : ["Set-up round: K{b0} (back), pm, k{s0} (left sleeve), pm, k{f0} (front), pm, k{s0} (right sleeve). The beginning-of-round marker is the fourth raglan marker. The yoke rounds below are counted from the next round, Round 1."]
        lines += [
            "Raglan increase \(round)\(flat ? " (RS)" : ""): \(inc). 8 sts increased.",
            "{if wF == 0}Work the raglan increase on every \(odd) from \(R) 1 to \(R) {lastFull} ({F} times).{else}Work the raglan increase on every \(odd) from \(R) 1 to \(R) {oddEnd}, then on every \(round) from \(R) {rapidStart} to \(R) {D}\(flat ? ", working the WS rows as \(incWS)" : "").{end}",
            "{if Xb > 0}At the same time, add width to the body without widening the sleeves: on every \(even) from \(R) 2 to \(R) {partialEnd} ({Xb} times), work \(flat ? bodyIncWS : bodyInc). 4 sts increased.{end}",
            "{if Xs > 0}At the same time, widen the sleeves without widening the body: on every \(even) from \(R) 2 to \(R) {partialEnd} ({Xs} times), work \(flat ? sleeveIncWS : sleeveInc). 4 sts increased.{end}",
            flat ? "Purl all the other WS rows." : "Knit all the other rounds.",
            "Continue until \(R) {D} is done. [{afterYoke} sts]",
            "The yoke should now measure {yokeDepthCm:len} from the cast-on edge.",
            "## Divide the body and sleeves",
            flat
                ? "Next row (RS): Knit to the 1st marker, remove it, place the {sleeveY} sleeve sts on hold, remove the 2nd marker, cast on {halfU} sts for the underarm, place a side marker, cast on {halfU} more, knit the back to the 3rd marker, remove it, place the {sleeveY} sleeve sts on hold, remove the 4th marker, cast on {halfU} sts, place a side marker, cast on {halfU} more, knit to the end. [{body} sts for the body]"
                : "Next round: Knit the back to the marker, remove it, place the {sleeveY} left sleeve sts on hold, remove the next marker, cast on {halfU} sts for the underarm, place a side marker, cast on {halfU} more, knit the front to the marker, remove it, place the {sleeveY} right sleeve sts on hold, remove the beginning-of-round marker, cast on {halfU} sts, place the new beginning-of-round marker, cast on {halfU} more. [{body} sts for the body]",
        ]
        q("yokeDepthCm", .length, "cmRows(neckRows + D)")
        section("Neckband and Yoke", lines)
    }

    // MARK: Round yoke

    mutating func roundYoke() {
        construction = "Top-down round yoke \(flat ? "cardigan, worked flat with picked-up bands" : "pullover, worked in the round"), the increases spread evenly over the yoke"
        q("bodyHeld", .stitches, "max(16, nearestMod(bodyT - 2 * u, 4, 0))")
        q("sleeveHeld", .stitches, "max(8, nearestMod(armT - u, 2, 0))")
        q("T", .stitches, "bodyHeld + 2 * sleeveHeld")
        // Enough increase rounds that none more than about doubles the stitches.
        q("kInc", .count, "clamp(ceil((T - co) / (0.85 * co)), 3, 6)")
        for i in 1...6 {
            let prev = i == 1 ? "co" : "n\(i - 1)"
            q("n\(i)", .stitches, "if(\(i) >= kInc, T, co + 2 * round((T - co) * \(i) / (2 * kInc)))")
            q("d\(i)", .stitches, "n\(i) - \(prev)")
            q("a\(i)", .stitches, "floor(\(prev) / max(1, d\(i)))")
            q("rem\(i)", .stitches, "\(prev) - a\(i) * d\(i)")
            q("short\(i)", .count, "d\(i) - rem\(i)")
            q("long\(i)", .stitches, "a\(i) + 1")
            // Increase rounds are spread evenly through the yoke, on RS (odd) rows.
            q("r\(i)", .rows, "2 * floor(((D - 4) * min(\(i), kInc) / kInc) / 2) + 1")
        }
        q("quarter", .stitches, "bodyHeld / 4")
        q("halfU", .stitches, "u / 2")
        q("half", .stitches, "bodyHeld / 2")
        q("body", .stitches, "bodyHeld + 2 * u")
        q("sleeve", .stitches, "sleeveHeld + u")
        q("yokeDepthCm", .length, "cmRows(neckRows + D)")
        checks.append(PatternCheck(expr: "d1 <= co && d2 <= n1 && d3 <= n2 && d4 <= n3 && d5 <= n4 && d6 <= n5", message: "The yoke more than doubles in one round; check the neck and chest.", when: nil))
        achieved["a"] = "cm(body)"
        achieved["b"] = "cm(sleeve)"

        var lines = castOnLines
        lines.append(flat
            ? "Work in stockinette (knit RS rows, purl WS rows). The yoke rows below are counted from the next row, Row 1 (RS)."
            : "Knit every round. The yoke rounds below are counted from the next round, Round 1.")
        for i in 1...6 {
            let before = i == 1 ? "co" : "n\(i - 1)"
            // Spread the leftover stitches through the round: some groups get one stitch more.
            let line = "\(round.capitalized) {r\(i)}: Increase {d\(i)} sts evenly: {if rem\(i) > 0}(k{a\(i)}, M1) {short\(i)} times, then (k{long\(i)}, M1) {rem\(i)} times{else}(k{a\(i)}, M1) {d\(i)} times{end}. [{n\(i)} sts, from {\(before)}]"
            lines.append(i <= 3 ? line : "{if kInc >= \(i)}" + line + "{end}")
        }
        lines.append("Work even until \(round.capitalized) {D} is done; the yoke should measure {yokeDepthCm:len} from the cast-on edge.")
        lines.append("## Divide the body and sleeves")
        lines.append(flat
            ? "Next row (RS): K{quarter} (right front), place the next {sleeveHeld} sts on hold for a sleeve, cast on {halfU} sts for the underarm, place a side marker, cast on {halfU} more, k{half} (back), place the next {sleeveHeld} sts on hold, cast on {halfU} sts, place a side marker, cast on {halfU} more, k{quarter} (left front). [{body} sts for the body]"
            : "Next round: The beginning of the round is now the centre back. K{quarter}, place the next {sleeveHeld} sts on hold for the left sleeve, cast on {halfU} sts for the underarm, place a side marker, cast on {halfU} more, k{half} (front), place the next {sleeveHeld} sts on hold for the right sleeve, cast on {halfU} sts, place a side marker, cast on {halfU} more, k{quarter} to the centre back. Remove the centre-back marker at the end of the next round; the side marker at the left underarm becomes the beginning of the round. [{body} sts for the body]")
        section("Neckband and Yoke", lines)
    }

    // MARK: Body

    mutating func body() {
        value("hemCm", .length, DesignSizing.depth(c.hem))
        q("hemT", .number, "sts(target_g)", internal: true)
        q("k", .count, "round((body - hemT) / 4)")
        q("absK", .count, "abs(k)")
        q("kLess1", .count, "absK - 1")
        q("bodyRows", .number, "rows(target_d - hemCm)", internal: true)
        q("bodyEvery", .rows, "max(2, 2 * floor((bodyRows - 6) / max(1, absK) / 2))")
        q("afterShaping", .stitches, "body - 4 * k")
        q("bodyToHem", .length, "target_d - hemCm")
        adjustment("hemAdj", from: "afterShaping", finish: c.hem, flat: flat)

        let markers = flat
            ? "The two side markers sit at the centres of the underarms; the shaping is worked at them."
            : "The beginning-of-round marker and the side marker sit at the centres of the underarms; the shaping is worked at them."
        let dec = flat
            ? "Shaping row (RS): *Knit to 3 sts before the side marker, k2tog, k1, slip marker, k1, ssk; repeat from * once more, knit to the end. 4 sts decreased."
            : "Shaping round: *K1, ssk, knit to 3 sts before the marker, k2tog, k1, slip marker; repeat from * once more. 4 sts decreased."
        let inc = flat
            ? "Shaping row (RS): *Knit to 1 st before the side marker, M1R, k1, slip marker, k1, M1L; repeat from * once more, knit to the end. 4 sts increased."
            : "Shaping round: *K1, M1L, knit to 1 st before the marker, M1R, k1, slip marker; repeat from * once more. 4 sts increased."
        let even = flat ? "Work in stockinette" : "Knit every round"
        section("Body", [
            markers,
            "{if absK == 0}\(even) until the body measures {bodyToHem:len} from the underarm.{end}",
            "{if k > 0}\(even) for {bodyEvery} \(rounds), then work a decrease:{elif k < 0}\(even) for {bodyEvery} \(rounds), then work an increase:{end}",
            "{if k > 0}\(dec){elif k < 0}\(inc){end}",
            "{if absK > 1}Repeat the shaping every {bodyEvery} \(rounds) {kLess1} more times. [{afterShaping} sts]{elif absK == 1}[{afterShaping} sts]{end}",
            "{if absK > 0}\(even) until the body measures {bodyToHem:len} from the underarm.{end}",
            c.stripes ? "Keep the stripes going as set." : "",
            "## Hem",
            "Change to the hem: work \(describe(c.hem, flat: flat)).\(adjustText("hemAdj")) [{hemAdjCount} sts]",
            "Work the hem for {hemCm:len}, then bind off loosely\(c.hem == .rolled ? "" : " in pattern").",
        ])
    }

    // MARK: Sleeves

    mutating func sleeves() {
        value("cuffCm", .length, DesignSizing.depth(c.cuff))
        q("cuffT", .number, "sts(target_f)", internal: true)
        let (m, _) = multiple(c.cuff, flat: false)
        q("cuffGoal", .stitches, "nearestMod(cuffT, \(m), 0)")
        q("sDecs", .count, "max(0, floor((sleeve - cuffGoal) / 2))")
        q("sLess1", .count, "sDecs - 1")
        q("sleeveRows", .number, "rows(target_e - cuffCm)", internal: true)
        q("sEvery", .rows, "max(2, floor((sleeveRows - 6) / max(1, sDecs)))")
        q("afterSleeve", .stitches, "sleeve - 2 * sDecs")
        q("sleeveToCuff", .length, "target_e - cuffCm")
        adjustment("cuffAdj", from: "afterSleeve", finish: c.cuff, flat: false)
        achieved["f"] = "cm(cuffAdjCount)"

        let held = c.construction == .raglan ? "sleeveY" : "sleeveHeld"
        section("Sleeves", [
            "Place the {\(held)} held sleeve sts on needles for working in the round. Starting at the centre of the underarm, pick up and knit {halfU} sts from the underarm cast-on, knit the sleeve sts, then pick up and knit {halfU} more. Place a marker for the beginning of the round. [{sleeve} sts]",
            "{if sDecs > 0}Knit {sEvery} rounds, then work a decrease round: K1, k2tog, knit to the last 3 sts, ssk, k1. 2 sts decreased.{end}",
            "{if sDecs > 1}Repeat the decrease round every {sEvery} rounds {sLess1} more times. [{afterSleeve} sts]{end}",
            "Knit until the sleeve measures {sleeveToCuff:len} from the underarm.",
            c.stripes ? "Keep the stripes going as on the body." : "",
            "## Cuff",
            "Work \(describe(c.cuff, flat: false)).\(adjustText("cuffAdj").replacingOccurrences(of: "first row", with: "first round")) [{cuffAdjCount} sts]",
            "Work the cuff for {cuffCm:len}, then bind off loosely\(c.cuff == .rolled ? "" : " in pattern").",
            "Work the second sleeve the same way.",
        ])
    }

    // MARK: Cardigan bands

    mutating func bands() {
        value("bandCm", .length, 2.5)
        let (m, r) = multiple(c.neckband, flat: true)
        q("bandPick", .stitches, "nearestMod(rows(target_c + target_d) * 0.75, \(m), \(r))")
        q("buttons", .count, "max(4, round((target_c + target_d) / 8))")
        section("Front Bands", [
            "Button band: With RS facing, starting at the left front neck, pick up and knit {bandPick} sts down the left front edge to the hem (about 3 sts for every 4 rows). Work \(describe(c.neckband, flat: true)) for {bandCm:len}, then bind off in pattern.",
            "Buttonhole band: Pick up {bandPick} sts up the right front edge from the hem to the neck in the same way. Work the band to half its depth, then make {buttons} buttonholes evenly spaced along it, the first and last about 1.5 cm from the ends: for each buttonhole, yo, k2tog (or work a 2-st one-row buttonhole). Finish the band and bind off in pattern.",
        ])
    }

    mutating func finishing() {
        section("Finishing", [
            "Weave in the ends\(c.stripes ? ", tidying the colour changes" : ""). Close any gaps at the underarms.",
            c.garment == .cardigan ? "Sew on {buttons} buttons opposite the buttonholes." : "",
            "Wash and block to the measurements in the schematic.",
        ])
    }
}
