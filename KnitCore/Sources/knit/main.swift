import Foundation
import KnitCore
import KnitImport
import KnitRender

let usage = """
    knit regrade <pattern.json> --chest <body> [measurements] [options]
    knit check <pattern.json>
    knit import <pattern.json> [--source-pdf <original.pdf>]   adds it to the app's library
    knit design [choice=value …] --pattern <pattern.json>
        writes a new pattern from design choices, e.g. construction=yoke garment=cardigan fit=relaxed
    knit read <original.pdf> [--ai] [--text] [--draft <draft.json>] [--pattern <pattern.json>]
        reads a pattern PDF (offline, or with Claude using ANTHROPIC_API_KEY)

    Body measurements (a number is cm; add "in" for inches, e.g. 38in):
      --chest --waist --hip --upper-arm --wrist --arm-length
      --armhole-depth --cross-back

    Options:
      --ease <dimension>=<length>      e.g. --ease chest=10cm
      --finished <dimension>=<length>  e.g. --finished bodyLength=70cm
      --gauge <sts>x<rows>             your gauge per 10 cm, e.g. --gauge 22x30
      --option <id>=<number>           e.g. --option long=0
      --units cm|in                    which unit to show first (both are shown)
      --pdf <file.pdf>                 write a PDF instead of text
      --source-pdf <original.pdf>      include the original pages the pattern lists

    Dimensions: \(GarmentMeasure.allCases.map(\.rawValue).joined(separator: ", "))
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func length(_ text: String) -> Double {
    guard let v = LengthParser.cm(from: text) else { fail("Not a length: \(text)") }
    return v
}

func keyValue(_ text: String) -> (String, String) {
    let parts = text.split(separator: "=", maxSplits: 1).map(String.init)
    guard parts.count == 2 else { fail("Expected name=value, got \(text)") }
    return (parts[0], parts[1])
}

func dimension(_ name: String) -> GarmentMeasure {
    guard let d = GarmentMeasure(rawValue: name) else { fail("Unknown dimension \(name)") }
    return d
}

var args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2 else { fail(usage) }
let command = args.removeFirst()
let path = args.removeFirst()

if command == "design" {
    designPattern([path] + args)
    exit(0)
}

if command == "read" {
    readPDF(URL(fileURLWithPath: path), args)
    exit(0)
}

let pattern: Pattern
do {
    pattern = try Pattern.load(from: URL(fileURLWithPath: path))
} catch {
    fail("Couldn't read \(path): \(error)")
}

switch command {
case "import":
    // Adds the pattern (and optionally its original PDF) to the app's library.
    var pdf: URL?
    if args.count == 2, args[0] == "--source-pdf" { pdf = URL(fileURLWithPath: args[1]) }
    do {
        let store = LibraryStore(root: LibraryStore.defaultRoot)
        var index = try store.load()
        let entry = try store.importPattern(from: URL(fileURLWithPath: path), sourcePDF: pdf, into: &index)
        print("Imported \(entry.name) into \(store.root.path)\(pdf == nil ? "" : ", with its PDF")")
    } catch {
        fail("Couldn't import: \(error)")
    }

case "check":
    do {
        print(try TextReport.designerCheck(pattern))
    } catch {
        fail("Check failed: \(error)")
    }

case "regrade":
    let bodyFlags: [String: BodyMeasure] = [
        "--chest": .chest, "--waist": .waist, "--hip": .hip, "--upper-arm": .upperArm,
        "--wrist": .wrist, "--arm-length": .armLength, "--armhole-depth": .armholeDepth,
        "--cross-back": .crossBack,
    ]
    var body: [BodyMeasure: Double] = [:]
    var ease: [GarmentMeasure: Double] = [:]
    var finished: [GarmentMeasure: Double] = [:]
    var options: [String: Double] = [:]
    var gauge: Gauge?
    var units = UnitPreference.cmFirst
    var pdfOut: URL?
    var sourcePDF: URL?

    while !args.isEmpty {
        let flag = args.removeFirst()
        guard !args.isEmpty else { fail("\(flag) needs a value") }
        let value = args.removeFirst()
        if let m = bodyFlags[flag] {
            body[m] = length(value)
            continue
        }
        switch flag {
        case "--ease":
            let (k, v) = keyValue(value)
            ease[dimension(k)] = length(v)
        case "--finished":
            let (k, v) = keyValue(value)
            finished[dimension(k)] = length(v)
        case "--option":
            let (k, v) = keyValue(value)
            guard let n = Double(v) else { fail("Option \(k) needs a number") }
            options[k] = n
        case "--gauge":
            let parts = value.lowercased().split(separator: "x").compactMap { Double($0) }
            guard parts.count == 2 else { fail("Gauge looks like 22x30 (stitches x rows per 10 cm)") }
            gauge = Gauge(stitchesPer10cm: parts[0], rowsPer10cm: parts[1], stitchPattern: pattern.gauge.stitchPattern)
        case "--units":
            units = value.hasPrefix("in") ? .inchFirst : .cmFirst
        case "--pdf":
            pdfOut = URL(fileURLWithPath: value)
        case "--source-pdf":
            sourcePDF = URL(fileURLWithPath: value)
        default:
            fail("Unknown flag \(flag)\n\n\(usage)")
        }
    }

    do {
        let plan = try EaseModel.plan(
            for: pattern, body: body, easeOverrides: ease, finishedOverrides: finished, options: options
        )
        let result = try Grader(pattern: pattern).grade(
            GradeRequest(targets: plan.gradeTargets, gauge: gauge, options: options, units: units)
        )
        if let pdfOut {
            let data = try PDFExporter.export(result, plan: plan, options: .init(sourcePDF: sourcePDF))
            try data.write(to: pdfOut)
            print("Wrote \(pdfOut.path)")
        } else {
            print(TextReport.render(result, fit: plan.targets))
            for note in plan.notes { print("Note: \(note)") }
        }
    } catch {
        fail("Couldn't regrade: \(error)")
    }

default:
    fail(usage)
}
