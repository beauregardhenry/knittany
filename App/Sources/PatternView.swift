import AppKit
import KnitCore
import SwiftUI
import UniformTypeIdentifiers

struct PatternView: View {
    @Environment(LibraryModel.self) private var model
    let entry: PatternEntry
    @State private var attachingPDF = false
    @State private var confirmingDelete = false

    var body: some View {
        if let pattern = model.pattern(entry.id) {
            Form {
                Section {
                    LabeledContent("Designer", value: pattern.designer ?? "–")
                    if let c = pattern.construction { LabeledContent("Construction") { Text(c).multilineTextAlignment(.trailing) } }
                    LabeledContent("Sizes", value: pattern.sizes.joined(separator: ", "))
                    LabeledContent("Gauge", value: MeasureFormatter().gauge(pattern.gauge))
                    if let ease = pattern.statedEase?[pattern.primaryDimension] {
                        LabeledContent("Designer's ease", value: "\(MeasureFormatter().length(ease)) at the \(pattern.primaryDimension.label.lowercased())")
                    }
                }

                Section {
                    HStack {
                        Button("New Project", systemImage: "plus") { model.addProject(patternID: entry.id) }
                            .buttonStyle(.borderedProminent)
                        Spacer()
                    }
                }

                Section("Original PDF") {
                    if entry.hasSourcePDF {
                        LabeledContent("Attached") {
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.store.sourcePDFURL(entry.id)]) }
                        }
                    } else {
                        Text(
                            (pattern.sourcePages ?? []).isEmpty
                                ? "No PDF attached."
                                : "Attach the original PDF so its chart pages (\((pattern.sourcePages ?? []).map(\.title).joined(separator: ", "))) can be included in exports."
                        )
                        .foregroundStyle(.secondary)
                    }
                    Button(entry.hasSourcePDF ? "Replace PDF…" : "Attach PDF…") { attachingPDF = true }
                }

                Section("Published measurements") {
                    Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 6) {
                        GridRow {
                            Text("").gridColumnAlignment(.leading)
                            ForEach(pattern.sizes, id: \.self) { Text($0).bold() }
                        }
                        ForEach(pattern.schematic, id: \.id) { s in
                            GridRow {
                                Text("\(s.id.prefix(1))  \(s.label)").gridColumnAlignment(.leading)
                                ForEach(Array(s.values.enumerated()), id: \.offset) { _, v in
                                    Text(MeasureFormatter.trim(v)).monospacedDigit()
                                }
                            }
                        }
                    }
                    .font(.callout)
                    Text("cm").font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    Button("Delete Pattern…", role: .destructive) { confirmingDelete = true }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(pattern.name)
            .fileImporter(isPresented: $attachingPDF, allowedContentTypes: [.pdf]) { result in
                if case .success(let url) = result { model.attachSourcePDF(url, to: entry.id) }
            }
            .confirmationDialog("Delete \(pattern.name)?", isPresented: $confirmingDelete) {
                Button("Delete", role: .destructive) { model.deletePattern(entry.id) }
            } message: {
                Text("Its projects are deleted too. The pattern's files go to the Trash.")
            }
        } else {
            Text("This pattern couldn't be read.").foregroundStyle(.secondary)
        }
    }
}
