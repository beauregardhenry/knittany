import KnitCore
import KnitRender
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// One pattern regraded for one person: settings on the left, the exported
/// pattern on the right, exactly as it will print.
struct ProjectView: View {
    @Environment(LibraryModel.self) private var model
    @State var project: Project
    @State private var output: Output?
    @State private var problem: String?
    @State private var exporting = false
    @State private var gaugePerInches = Locale.current.measurementSystem == .us
    @State private var mode = Mode.pattern
    @AppStorage(TextSize.key) private var textSize = TextSize.standard

    enum Mode { case pattern, knit }

    struct Output {
        var result: GradeResult
        var plan: FitPlan
        var pdf: Data
    }

    var pattern: KnitCore.Pattern? { model.pattern(project.patternID) }

    /// Everything that changes the regraded pattern; ticking off steps or editing notes doesn't.
    struct RegradeInputs: Equatable {
        var project: Project
        init(_ p: Project) {
            project = p
            project.progress = nil
            project.notes = ""
            project.name = ""
        }
    }

    var regradeInputs: RegradeInputs { RegradeInputs(project) }

    struct RegradeKey: Equatable {
        var inputs: RegradeInputs
        var textSize: TextSize
    }
    var person: Person? { model.person(project.personID) }

    var body: some View {
        Group {
            if mode == .knit {
                // While knitting, the instructions get the whole window.
                preview.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    settings
                        .frame(minWidth: 340, idealWidth: 390, maxWidth: 480, maxHeight: .infinity)
                    preview
                        .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationTitle(project.name)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $mode) {
                    Text("Pattern").tag(Mode.pattern)
                    Text("Knit").tag(Mode.knit)
                }
                .pickerStyle(.segmented)
                .help("Pattern shows the regraded pattern as it prints; Knit is a checklist with a row counter")
            }
            ToolbarItem {
                Button("Export PDF…", systemImage: "square.and.arrow.up") { exporting = true }
                    .disabled(output == nil)
            }
        }
        .onChange(of: project) { model.update(project) }
        .task(id: RegradeKey(inputs: regradeInputs, textSize: textSize)) {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            regenerate()
        }
        .onChange(of: model.index.people) { regenerate() }
        .fileExporter(
            isPresented: $exporting,
            document: PDFFile(data: output?.pdf ?? Data()),
            contentType: .pdf,
            defaultFilename: project.name
        ) { result in
            if case .failure(let error) = result { model.errorMessage = "Couldn't save the PDF: \(error)" }
        }
    }

    func regenerate() {
        guard let pattern else {
            problem = "The pattern for this project is missing."
            output = nil
            return
        }
        do {
            let (result, plan) = try project.regrade(pattern: pattern, person: person)
            let pdf = try PDFExporter.export(result, plan: plan, options: .init(
                personName: person?.name, sourcePDF: model.sourcePDF(project.patternID), textScale: textSize.pdfScale
            ))
            output = Output(result: result, plan: plan, pdf: pdf)
            problem = nil
        } catch {
            output = nil
            if person == nil {
                problem = "Choose who this is for, or enter a finished chest measurement under Changes."
            } else if person?.measurements[.chest] == nil && project.finishedOverrides[pattern.primaryDimension] == nil {
                problem = "Enter \(person?.name ?? "their")'s chest measurement to regrade."
            } else if pattern.statedEase?[pattern.primaryDimension] == nil && project.easeOverrides[pattern.primaryDimension] == nil {
                problem = "This pattern doesn't say how much ease it has. Enter the ease you'd like at the \(pattern.primaryDimension.label.lowercased()) under Ease, on the left."
            } else {
                problem = "Couldn't regrade: \(error)"
            }
        }
    }

    // MARK: Settings

    var settings: some View {
        Form {
            Section {
                TextField("Project name", text: $project.name)
                Picker("Knitting for", selection: $project.personID) {
                    Text("Nobody chosen").tag(UUID?.none)
                    ForEach(model.people) { p in Text(p.name).tag(UUID?.some(p.id)) }
                }
                LabeledContent("Pattern", value: pattern?.name ?? "missing")
                Picker("Show first", selection: $project.units) {
                    Text("cm").tag(UnitPreference.cmFirst)
                    Text("inches").tag(UnitPreference.inchFirst)
                }
                .pickerStyle(.segmented)
            }

            if let options = pattern?.options, !options.isEmpty {
                Section("Version") {
                    ForEach(options, id: \.id) { o in
                        Toggle(o.label, isOn: Binding(
                            get: { (project.options[o.id] ?? o.defaultValue) != 0 },
                            set: { project.options[o.id] = $0 ? 1 : 0 }
                        ))
                    }
                }
            }

            fitSection
            changesSection
            gaugeSection

            Section("Notes") {
                TextEditor(text: $project.notes).frame(minHeight: 50)
            }

            Section {
                Button("Delete Project", role: .destructive) { model.deleteProject(project.id) }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    var fitSection: some View {
        Section {
            if output == nil, let pattern, pattern.statedEase?[pattern.primaryDimension] == nil {
                // Without the designer's ease there's nothing to regrade from until the knitter gives one.
                let d = pattern.primaryDimension
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(d.label) ease")
                        Spacer()
                        LengthField(
                            title: "Ease",
                            cm: Binding(get: { project.easeOverrides[d] }, set: { project.easeOverrides[d] = $0 }),
                            units: project.units, prompt: "enter ease"
                        )
                        .labelsHidden()
                        .frame(width: 130)
                    }
                    if let sizes = pattern.schematic.first(where: { $0.dimension == d }) {
                        Text("The pattern doesn't say how much ease it has. Its finished \(d.label.lowercased()) is \(sizes.values.map { LengthText.format($0, project.units) }.joined(separator: ", ")) for sizes \(pattern.sizes.joined(separator: ", ")); compare with \(person?.name ?? "the wearer")'s measurement.")
                            .scaledFont(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let output {
                Text("Closest published sizes: \(output.result.position).").scaledFont(.callout)
                ForEach(Array(output.plan.targets.enumerated()), id: \.offset) { _, t in
                    fitRow(t)
                }
                ForEach(easeNeeded(output), id: \.self) { d in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.label)
                            Text("measured, but the pattern's ease isn't known").scaledFont(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        LengthField(
                            title: "Ease",
                            cm: Binding(get: { project.easeOverrides[d] }, set: { project.easeOverrides[d] = $0 }),
                            units: project.units, prompt: "enter ease"
                        )
                        .labelsHidden()
                        .frame(width: 130)
                    }
                }
            }
        } header: {
            Text("Ease")
        } footer: {
            Text("Ease is the difference between the body and the finished garment. Leave a field empty to use the designer's ease, or the ease worked out from the pattern's sizes.")
                .scaledFont(.caption).foregroundStyle(.secondary)
        }
    }

    /// Measured dimensions whose ease can't be worked out, so the knitter has to give it.
    func easeNeeded(_ output: Output) -> [GarmentMeasure] {
        let used = Set(output.plan.targets.map(\.dimension))
        var seen = Set<GarmentMeasure>()
        return output.result.schematic.map(\.entry.dimension).filter { d in
            guard !used.contains(d), seen.insert(d).inserted, let bm = d.bodyMeasure else { return false }
            return person?.measurements[bm] != nil
        }
    }

    @ViewBuilder
    func fitRow(_ t: FitTarget) -> some View {
        let units = project.units
        switch t.source {
        case .bodyPlusEase(let body, let ease, let from):
            let binding = Binding<Double?>(
                get: { project.easeOverrides[t.dimension] },
                set: { project.easeOverrides[t.dimension] = $0 }
            )
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.dimension.label)
                    Text("body \(LengthText.both(body, units)) → \(LengthText.both(t.finished, units))")
                        .scaledFont(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                LengthField(
                    title: "Ease", cm: binding, units: units,
                    prompt: "\(LengthText.format(ease, units))\(from == .inferred ? " (inferred)" : "")"
                )
                .labelsHidden()
                .frame(width: 130)
            }
        case .override, .designerGrading:
            EmptyView()
        }
    }

    @ViewBuilder
    var changesSection: some View {
        Section {
            if let output {
                ForEach(output.result.schematic, id: \.entry.id) { s in
                    let binding = Binding<Double?>(
                        get: { project.finishedOverrides[s.entry.dimension] },
                        set: { project.finishedOverrides[s.entry.dimension] = $0 }
                    )
                    HStack {
                        Text("\(s.entry.id)  \(s.entry.label)")
                        Spacer()
                        LengthField(title: s.entry.label, cm: binding, units: project.units, prompt: LengthText.format(s.target, project.units))
                            .labelsHidden()
                            .frame(width: 110)
                    }
                }
            }
        } header: {
            Text("Changes")
        } footer: {
            Text("Type a finished measurement to change it, e.g. a longer body. The grey value is what you get now.")
                .scaledFont(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    var gaugeSection: some View {
        let factor = gaugePerInches ? 10.16 / 10 : 1
        Section {
            Toggle("Use my gauge", isOn: Binding(
                get: { project.gauge != nil },
                set: { project.gauge = $0 ? (project.gauge ?? pattern?.gauge) : nil }
            ))
            if let g = project.gauge {
                Picker("Per", selection: $gaugePerInches) {
                    Text("10 cm").tag(false)
                    Text("4 in").tag(true)
                }
                .pickerStyle(.segmented)
                LabeledContent("Stitches") {
                    NumberField(title: "Stitches", value: Binding(
                        get: { (g.stitchesPer10cm * factor * 4).rounded() / 4 },
                        set: { if let v = $0, v > 0 { project.gauge?.stitchesPer10cm = v / factor } }
                    ))
                    .labelsHidden().frame(width: 70)
                }
                LabeledContent("Rows") {
                    NumberField(title: "Rows", value: Binding(
                        get: { (g.rowsPer10cm * factor * 4).rounded() / 4 },
                        set: { if let v = $0, v > 0 { project.gauge?.rowsPer10cm = v / factor } }
                    ))
                    .labelsHidden().frame(width: 70)
                }
                .id(gaugePerInches)
                ForEach(g.problems, id: \.self) {
                    Label($0, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).scaledFont(.callout)
                }
            }
        } header: {
            Text("Gauge")
        } footer: {
            Text("Pattern gauge: \(pattern.map { MeasureFormatter(preference: project.units).gauge($0.gauge) } ?? "–"). Measure a washed and blocked swatch.")
                .scaledFont(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Preview

    var preview: some View {
        VStack(spacing: 0) {
            if let problem {
                ContentUnavailableView("Not regraded yet", systemImage: "ruler", description: Text(problem))
            } else if let output {
                if !output.result.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Check before knitting", systemImage: "exclamationmark.triangle.fill").bold()
                        ForEach(output.result.warnings, id: \.self) { Text("• \($0)").scaledFont(.callout) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.orange.opacity(0.15))
                }
                switch mode {
                case .pattern:
                    PDFPreview(data: output.pdf)
                case .knit:
                    KnitView(result: output.result, progress: Binding(
                        get: { project.progress ?? KnittingProgress() },
                        set: { project.progress = $0 }
                    ))
                }
            } else {
                ProgressView()
            }
        }
    }
}

struct PDFPreview: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .windowBackgroundColor
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        guard view.document?.dataRepresentation() != data else { return }
        let page = view.currentPage.flatMap { view.document?.index(for: $0) } ?? 0
        view.document = PDFDocument(data: data)
        if let p = view.document?.page(at: min(page, (view.document?.pageCount ?? 1) - 1)) {
            view.go(to: p)
        }
    }
}

struct PDFFile: FileDocument {
    static let readableContentTypes: [UTType] = [.pdf]
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
