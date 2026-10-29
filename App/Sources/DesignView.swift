import KnitCore
import KnitRender
import SwiftUI

/// What's being designed: a new pattern, or an existing designed pattern being changed.
struct DesignSession: Identifiable {
    let id = UUID()
    var choices: DesignChoices
    /// The library pattern this edits, if any.
    var patternID: UUID?
}

/// Design a sweater from scratch: choices on the left, the pattern it makes on
/// the right, regraded for a person or shown in a standard size.
struct DesignView: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var session: DesignSession
    @State private var previewFor: PreviewTarget = .size(2)
    @State private var pdf: Data?
    @State private var problem: String?

    enum PreviewTarget: Hashable {
        case size(Int)
        case person(UUID)
    }

    var c: Binding<DesignChoices> { $session.choices }

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                form.frame(minWidth: 360, idealWidth: 400, maxWidth: 460, maxHeight: .infinity)
                preview.frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack {
                Text("Drawn for the \(session.choices.sizeChart.label.lowercased()) standard sizes \(session.choices.sizeChart.sizes.first!)–\(session.choices.sizeChart.sizes.last!); a project regrades it to anyone's measurements.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(session.patternID == nil ? "Save Pattern" : "Save Changes") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(problem != nil)
            }
            .padding(12)
        }
        .frame(minWidth: 960, idealWidth: 1180, minHeight: 560, idealHeight: 820)
        .task(id: PreviewKey(choices: session.choices, target: previewFor, people: model.index.people)) {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            render()
        }
    }

    struct PreviewKey: Equatable {
        var choices: DesignChoices
        var target: PreviewTarget
        var people: [Person]
    }

    // MARK: Choices

    var form: some View {
        Form {
            Section {
                TextField("Name", text: c.name, prompt: Text(session.choices.defaultName))
                Picker("Construction", selection: c.construction) {
                    Text("Raglan").tag(DesignChoices.Construction.raglan)
                    Text("Round yoke").tag(DesignChoices.Construction.yoke)
                }
                .pickerStyle(.segmented)
                Picker("Garment", selection: c.garment) {
                    Text("Pullover").tag(GarmentType.pullover)
                    Text("Cardigan").tag(GarmentType.cardigan)
                }
                .pickerStyle(.segmented)
                Picker("Sizes", selection: Binding(get: { session.choices.sizeChart }, set: { session.choices.chart = $0 })) {
                    ForEach(SizeChart.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Neckline", selection: c.neck) {
                    Text("Crew").tag(DesignChoices.Neck.crew)
                    Text("Wide").tag(DesignChoices.Neck.wide)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Sweater")
            } footer: {
                Text("Sizes follow the Craft Yarn Council's women's or men's chart. Both constructions are knitted top-down in one piece, so there's no sewing. A raglan has four diagonal lines from the neck to the underarms; a round yoke grows in a circle, which suits colourwork and stripes.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Fit and length") {
                Picker("Fit at the chest", selection: c.fit) {
                    Text("Close (5 cm / 2″ ease)").tag(DesignChoices.Fit.close)
                    Text("Classic (10 cm / 4″)").tag(DesignChoices.Fit.classic)
                    Text("Relaxed (18 cm / 7″)").tag(DesignChoices.Fit.relaxed)
                    Text("Oversized (30 cm / 12″)").tag(DesignChoices.Fit.oversized)
                }
                Picker("Body length", selection: c.length) {
                    Text("Cropped, above the waist").tag(DesignChoices.Length.cropped)
                    Text("To the hip").tag(DesignChoices.Length.hip)
                    Text("Tunic").tag(DesignChoices.Length.tunic)
                }
                Picker("Body shape", selection: c.bodyShape) {
                    Text("Straight").tag(DesignChoices.BodyShape.straight)
                    Text("A-line, wider at the hem").tag(DesignChoices.BodyShape.aLine)
                    Text("Shaped to the hip").tag(DesignChoices.BodyShape.fitted)
                }
                Picker("Sleeves", selection: c.sleeveLength) {
                    Text("Full length").tag(DesignChoices.SleeveLength.full)
                    Text("Three-quarter").tag(DesignChoices.SleeveLength.threeQuarter)
                    Text("Elbow").tag(DesignChoices.SleeveLength.elbow)
                    Text("Short").tag(DesignChoices.SleeveLength.short)
                }
                Picker("Sleeve shape", selection: c.sleeveTaper) {
                    Text("Tapered to the cuff").tag(DesignChoices.SleeveTaper.tapered)
                    Text("Straight").tag(DesignChoices.SleeveTaper.straight)
                }
            }

            Section("Edges") {
                finishPicker("Hem", c.hem)
                finishPicker("Cuffs", c.cuff)
                finishPicker(session.choices.garment == .cardigan ? "Neck and front bands" : "Neckband", c.neckband)
                Toggle("Stripes in two colours", isOn: c.stripes)
            }

            Section {
                LabeledContent("Stitches") {
                    NumberField(title: "Stitches", value: Binding(
                        get: { session.choices.gauge.stitchesPer10cm },
                        set: { if let v = $0, v > 0 { session.choices.gauge.stitchesPer10cm = v } }
                    ))
                    .labelsHidden().frame(width: 70)
                }
                LabeledContent("Rows") {
                    NumberField(title: "Rows", value: Binding(
                        get: { session.choices.gauge.rowsPer10cm },
                        set: { if let v = $0, v > 0 { session.choices.gauge.rowsPer10cm = v } }
                    ))
                    .labelsHidden().frame(width: 70)
                }
                TextField("Needle", text: Binding(
                    get: { session.choices.gauge.needle ?? "" },
                    set: { session.choices.gauge.needle = $0.isEmpty ? nil : $0 }
                ))
            } header: {
                Text("Gauge in stockinette, per 10 cm / 4″")
            } footer: {
                Text("From a washed and blocked swatch in the yarn you'll use. Every number in the pattern is worked out from it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    func finishPicker(_ title: String, _ value: Binding<DesignChoices.Finish>) -> some View {
        Picker(title, selection: value) {
            Text("2x2 rib").tag(DesignChoices.Finish.rib2x2)
            Text("1x1 rib").tag(DesignChoices.Finish.rib1x1)
            Text("Garter").tag(DesignChoices.Finish.garter)
            Text("Rolled edge").tag(DesignChoices.Finish.rolled)
        }
    }

    // MARK: Preview

    var preview: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Preview for", selection: $previewFor) {
                    ForEach(Array(session.choices.sizeChart.sizes.enumerated()), id: \.offset) { i, name in
                        Text("Size \(name)").tag(PreviewTarget.size(i))
                    }
                    if !model.people.isEmpty {
                        Divider()
                        ForEach(model.people) { p in Text(p.name).tag(PreviewTarget.person(p.id)) }
                    }
                }
                .frame(maxWidth: 260)
                Spacer()
            }
            .padding(10)
            Divider()
            if let problem {
                ContentUnavailableView("Can't make this design", systemImage: "exclamationmark.triangle", description: Text(problem))
            } else if let pdf {
                PDFPreview(data: pdf)
            } else {
                ProgressView().frame(maxHeight: .infinity)
            }
        }
    }

    func render() {
        do {
            let pattern = try Designer.pattern(from: session.choices)
            let result: GradeResult
            var plan = FitPlan(targets: [], notes: [])
            var name: String?
            switch previewFor {
            case .size(let wanted):
                let i = min(wanted, pattern.sizes.count - 1)
                let targets = Dictionary(uniqueKeysWithValues: pattern.schematic.map { ($0.dimension, $0.values[i]) })
                result = try Grader(pattern: pattern).grade(GradeRequest(targets: targets))
            case .person(let id):
                guard let person = model.person(id), person.measurements[.chest] != nil else {
                    throw PatternError("Enter \(model.person(id)?.name ?? "their") chest measurement to preview the design for them.")
                }
                let project = Project(name: "", patternID: UUID(), personID: id, units: person.units)
                (result, plan) = try project.regrade(pattern: pattern, person: person)
                name = person.name
            }
            pdf = try PDFExporter.export(result, plan: plan, options: .init(personName: name))
            problem = nil
        } catch {
            problem = "\(error)"
            pdf = nil
        }
    }

    func save() {
        do {
            let pattern = try Designer.pattern(from: session.choices)
            if let id = session.patternID {
                model.replacePattern(id, with: pattern)
            } else {
                model.savePattern(pattern, sourcePDF: nil)
            }
            dismiss()
        } catch {
            problem = "\(error)"
        }
    }
}
