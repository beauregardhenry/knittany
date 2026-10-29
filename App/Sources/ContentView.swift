import KnitCore
import SwiftUI
import UniformTypeIdentifiers

/// Phase 1 preview: open a pattern file, enter a chest measurement, read the
/// regraded pattern. The full app (people, measurements, schematics, charts,
/// PDF export) comes in phase 2.
struct ContentView: View {
    @State private var pattern: KnitCore.Pattern?
    @State private var patternName = "No pattern open"
    @State private var chest = ""
    @State private var units = UnitPreference.cmFirst
    @State private var output = ""
    @State private var showingImporter = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button("Open Pattern…") { showingImporter = true }
                Text(patternName).foregroundStyle(.secondary)
                Spacer()
                Picker("Units", selection: $units) {
                    Text("cm first").tag(UnitPreference.cmFirst)
                    Text("inches first").tag(UnitPreference.inchFirst)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            HStack(spacing: 12) {
                TextField("Body chest, e.g. 94 cm or 37in", text: $chest)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .onSubmit(regrade)
                Button("Regrade", action: regrade)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(pattern == nil)
            }
            ScrollView {
                Text(output.isEmpty ? "Open a pattern file and enter a chest measurement." : output)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(16)
        .onChange(of: units) { if !output.isEmpty { regrade() } }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            open(result)
        }
    }

    private func open(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let p = try KnitCore.Pattern.load(from: url)
            pattern = p
            patternName = [p.name, p.designer].compactMap { $0 }.joined(separator: " — ")
            output = ""
        } catch {
            output = "Couldn't open the pattern: \(error)"
        }
    }

    private func regrade() {
        guard let pattern else { return }
        guard let cm = LengthParser.cm(from: chest) else {
            output = "Enter the chest as a number, e.g. 94 (cm) or 37in."
            return
        }
        do {
            let fit = try EaseModel.targets(for: pattern, body: [.chest: cm])
            var targets: [GarmentMeasure: Double] = [:]
            for t in fit { targets[t.dimension] = t.finished }
            let result = try Grader(pattern: pattern).grade(GradeRequest(targets: targets, units: units))
            output = TextReport.render(result, fit: fit)
        } catch {
            output = "Couldn't regrade: \(error)"
        }
    }
}
