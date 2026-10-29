import Foundation
import KnitCore

/// `knit design`: writes a pattern from design choices given as name=value.
func designPattern(_ args: [String]) {
    var fields: [String: Any] = [:]
    var out: URL?
    var gauge = (20.0, 28.0)
    var i = 0
    while i < args.count {
        let a = args[i]
        if a == "--pattern", i + 1 < args.count {
            out = URL(fileURLWithPath: args[i + 1])
            i += 2
            continue
        }
        let (k, v) = keyValue(a)
        switch k {
        case "stripes": fields[k] = v == "yes" || v == "true" || v == "1"
        case "gauge":
            let parts = v.lowercased().split(separator: "x").compactMap { Double($0) }
            guard parts.count == 2 else { fail("Gauge looks like 20x28 (stitches x rows per 10 cm)") }
            gauge = (parts[0], parts[1])
        default: fields[k] = v
        }
        i += 1
    }
    let defaults = DesignChoices()
    var json = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(defaults))) as? [String: Any] ?? [:]
    json.merge(fields) { _, new in new }
    json["gauge"] = ["stitchesPer10cm": gauge.0, "rowsPer10cm": gauge.1, "stitchPattern": "stockinette stitch"]
    do {
        let choices = try JSONDecoder().decode(DesignChoices.self, from: JSONSerialization.data(withJSONObject: json))
        let pattern = try Designer.pattern(from: choices)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(pattern)
        if let out { try data.write(to: out); print("Wrote \(out.path)") } else { print(String(decoding: data, as: UTF8.self)) }
    } catch {
        fail("Couldn't design: \(error)")
    }
}
