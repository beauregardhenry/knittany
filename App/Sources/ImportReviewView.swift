import KnitCore
import KnitImport
import PDFKit
import SwiftUI

/// Check and correct what was read from a PDF before it becomes a pattern.
/// The original PDF sits alongside for comparison.
struct ImportReviewView: View {
    @Binding var draft: ImportDraft
    let pdf: URL
    let cancel: () -> Void
    let save: (KnitCore.Pattern) -> Void

    @State private var showUnused = false
    @State private var saveError: String?

    var problems: [String] { DraftBuilder.problems(draft) }

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                form.frame(minWidth: 520, idealWidth: 620)
                OriginalPDF(url: pdf).frame(minWidth: 320, idealWidth: 420)
            }
            Divider()
            HStack {
                let p = problems
                if let first = p.first {
                    Label(p.count == 1 ? first : "\(first) (and \(p.count - 1) more)", systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red).lineLimit(2)
                } else {
                    Label("Ready to save. Read through the instructions once; the numbers in {braces} are regraded.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Spacer()
                Button("Cancel", role: .cancel) { cancel() }.keyboardShortcut(.cancelAction)
                Button("Save Pattern") {
                    do {
                        save(try DraftBuilder.pattern(from: draft))
                    } catch {
                        saveError = "\(error)"
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!p.isEmpty)
            }
            .padding(12)
        }
        .frame(minWidth: 900, idealWidth: 1150, minHeight: 520, idealHeight: 820)
        .alert("Couldn't save the pattern", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    var form: some View {
        Form {
            if !draft.notes.isEmpty || !problems.isEmpty {
                Section {
                    ForEach(problems, id: \.self) { Label($0, systemImage: "xmark.octagon.fill").foregroundStyle(.red) }
                    ForEach(draft.notes, id: \.self) { Label($0, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                } header: {
                    Text("Check")
                }
            }

            Section("Pattern") {
                LabeledContent("Read", value: draft.method == .claude ? "with Claude" : "on this Mac")
                TextField("Name", text: $draft.name)
                TextField("Designer", text: $draft.designer)
                Picker("Garment", selection: $draft.garment) {
                    Text("Not sure").tag(GarmentType?.none)
                    Text("Pullover").tag(GarmentType?.some(.pullover))
                    Text("Cardigan").tag(GarmentType?.some(.cardigan))
                }
            }

            sizesSection
            measurementsSection
            numbersSection
            instructionsSection
            pagesSection
        }
        .formStyle(.grouped)
    }

    // MARK: Sizes and gauge

    var sizesSection: some View {
        Section {
            TextField("Sizes", text: Binding(
                get: { draft.sizes.joined(separator: ", ") },
                set: { draft.sizes = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
            ))
            LabeledContent("Stitches in 10 cm / 4 in") {
                NumberField(title: "Stitches", value: Binding(get: { draft.gauge.stitchesPer10cm }, set: { draft.gauge.stitchesPer10cm = $0 ?? 0 }))
                    .labelsHidden().frame(width: 70)
            }
            LabeledContent("Rows in 10 cm / 4 in") {
                NumberField(title: "Rows", value: Binding(get: { draft.gauge.rowsPer10cm }, set: { draft.gauge.rowsPer10cm = $0 ?? 0 }))
                    .labelsHidden().frame(width: 70)
            }
            ForEach(Gauge.problems(stitchesPer10cm: draft.gauge.stitchesPer10cm, rowsPer10cm: draft.gauge.rowsPer10cm), id: \.self) {
                Label($0, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).scaledFont(.callout)
            }
            TextField("Stitch pattern", text: $draft.gauge.stitchPattern)
            TextField("Needle", text: $draft.gauge.needle)
            LabeledContent("Designer's chest ease") {
                LengthField(title: "Ease", cm: $draft.chestEase, units: .cmFirst, prompt: "none given")
                    .labelsHidden().frame(width: 140)
            }
        } header: {
            Text("Sizes and gauge")
        } footer: {
            Text("Size names in order, separated by commas. Gauge is the number of stitches and rows in a 10 cm / 4 in square of the swatch; patterns that give it over another span, like \"8 sts to 2 inches\", are converted.").scaledFont(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Measurements

    var measurementsSection: some View {
        Section {
            ForEach($draft.measurements) { $m in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        TextField("Label", text: $m.label).labelsHidden()
                        Picker("Measurement", selection: $m.dimension) {
                            Text("Not used").tag(GarmentMeasure?.none)
                            ForEach(GarmentMeasure.allCases, id: \.self) { Text($0.label).tag(GarmentMeasure?.some($0)) }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                        Button("Remove", systemImage: "minus.circle") { draft.measurements.removeAll { $0.id == m.id } }
                            .labelStyle(.iconOnly).buttonStyle(.borderless)
                    }
                    ValuesField(values: $m.values, sizes: draft.sizes, unit: "cm")
                }
            }
            Button("Add Measurement", systemImage: "plus") {
                let used = Set(draft.measurements.map(\.id))
                let id = "abcdefghijklmnopqrstuvwxyz".map(String.init).first { !used.contains($0) } ?? "m\(draft.measurements.count + 1)"
                draft.measurements.append(DraftMeasurement(id: id, label: "New measurement", dimension: nil, values: Array(repeating: 0, count: draft.sizes.count)))
            }
            .buttonStyle(.borderless)
        } header: {
            Text("Finished measurements")
        } footer: {
            Text("Per size, in cm. Choose which garment measurement each one is; the chest picks the size. Stitch counts follow these when you regrade.")
                .scaledFont(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Numbers

    var numbersSection: some View {
        let used = draft.usedNumberIDs
        let dimensions = Set(draft.measurements.compactMap(\.dimension))
        return Section {
            Toggle("Show numbers outside the instructions", isOn: $showUnused)
            ForEach($draft.numbers) { $n in
                if showUnused || used.contains(n.id) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("{\(n.id)}").scaledFont(.body, monospaced: true).bold()
                            Spacer()
                            Picker("Kind", selection: $n.kind) {
                                Text("Stitches").tag(QuantityKind.stitches)
                                Text("Rows").tag(QuantityKind.rows)
                                Text("Times").tag(QuantityKind.count)
                                Text("Length (cm)").tag(QuantityKind.length)
                                Text("Yarn (m)").tag(QuantityKind.yarn)
                                Text("Number").tag(QuantityKind.number)
                            }
                            .labelsHidden().frame(width: 130)
                            Picker("Follows", selection: Binding(get: { n.driver == .chest ? nil : n.driver }, set: { n.driver = $0 })) {
                                Text("Chest").tag(GarmentMeasure?.none)
                                ForEach(GarmentMeasure.allCases.filter { $0 != .chest && dimensions.contains($0) }, id: \.self) {
                                    Text($0.label).tag(GarmentMeasure?.some($0))
                                }
                            }
                            .labelsHidden().frame(width: 190)
                        }
                        Text(n.context).scaledFont(.caption).foregroundStyle(.secondary).lineLimit(2)
                        ValuesField(values: $n.values, sizes: draft.sizes, unit: unit(n.kind))
                    }
                }
            }
        } header: {
            Text("Numbers that change with size (\(used.count))")
        } footer: {
            Text("Each number is regraded along the measurement it follows: body stitches follow the chest, sleeve stitches the upper arm, lengths the body or sleeve length.")
                .scaledFont(.caption).foregroundStyle(.secondary)
        }
    }

    func unit(_ kind: QuantityKind) -> String {
        switch kind {
        case .stitches: "sts"
        case .rows: "rows"
        case .count: "times"
        case .length: "cm"
        case .yarn: "m"
        case .number: ""
        }
    }

    // MARK: Instructions

    var instructionsSection: some View {
        Section {
            ForEach($draft.sections) { $s in
                DisclosureGroup {
                    TextEditor(text: Binding(
                        get: { s.lines.joined(separator: "\n") },
                        set: { s.lines = $0.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
                    ))
                    .scaledFont(.callout)
                    .frame(minHeight: 120, idealHeight: CGFloat(min(400, 22 * s.lines.count)))
                } label: {
                    HStack {
                        Toggle("Include", isOn: $s.include).labelsHidden()
                        TextField("Title", text: $s.title).labelsHidden()
                        Text("\(s.lines.count) lines").scaledFont(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Instructions")
        } footer: {
            Text("One step per line. {name} is a number from the list above, {name:len} a length printed in cm and inches. Lines starting with ## are sub-headings. Untick sections that aren't knitting steps.")
                .scaledFont(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Pages

    var pagesSection: some View {
        Section {
            ForEach(draft.chartPages.indices, id: \.self) { i in
                HStack {
                    Text("Page \(draft.chartPages[i].page)").monospacedDigit().frame(width: 70, alignment: .leading)
                    TextField("Title", text: $draft.chartPages[i].title).labelsHidden()
                    Button("Remove", systemImage: "minus.circle") { draft.chartPages.remove(at: i) }
                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                }
            }
            AddPageRow { page in
                draft.chartPages.append(DraftPage(title: "Page \(page)", page: page))
                draft.chartPages.sort { $0.page < $1.page }
            }
        } header: {
            Text("Original pages to include")
        } footer: {
            Text("Charts and other pages that don't change with size are printed from the original PDF at the end of the regraded pattern.")
                .scaledFont(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Per-size values typed as "92, 102, 112".
struct ValuesField: View {
    @Binding var values: [Double]
    let sizes: [String]
    let unit: String
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            TextField("Values", text: $text, prompt: Text(sizes.joined(separator: ", ")))
                .labelsHidden()
                .scaledFont(.callout).monospacedDigit()
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { if !focused { commit() } }
                .onAppear(perform: load)
                .onChange(of: values) { if !focused { load() } }
            if !unit.isEmpty { Text(unit).scaledFont(.caption).foregroundStyle(.secondary) }
            if values.count != sizes.count {
                Text("\(values.count) of \(sizes.count)").scaledFont(.caption).foregroundStyle(.red)
            }
        }
    }

    func load() { text = values.map(MeasureFormatter.trim).joined(separator: ", ") }

    func commit() {
        values = text.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == " " }).compactMap { Double($0) }
        load()
    }
}

struct AddPageRow: View {
    let add: (Int) -> Void
    @State private var page: Int?

    var body: some View {
        HStack {
            TextField("Page", value: $page, format: .number, prompt: Text("page number")).frame(width: 110).labelsHidden()
            Button("Add Page", systemImage: "plus") {
                if let page, page > 0 { add(page) }
                self.page = nil
            }
            .buttonStyle(.borderless)
            .disabled((page ?? 0) <= 0)
        }
    }
}

/// The designer's PDF, for comparing against the draft.
struct OriginalPDF: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .windowBackgroundColor
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {}
}
