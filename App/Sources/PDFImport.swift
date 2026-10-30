import KnitCore
import KnitImport
import SwiftUI

/// One pattern PDF on its way into the library: choose how to read it, read
/// it, then check and correct the draft before saving.
@MainActor
@Observable
final class PDFImport: Identifiable {
    enum Phase {
        case choosing
        case reading(ImportDraft.Method)
        case reviewing
        case failed(String)
    }

    let id = UUID()
    /// A private copy, so the file stays readable after the open panel's access ends.
    let pdf: URL
    var phase: Phase = .choosing
    var draft: ImportDraft?
    var received = 0
    private var task: Task<Void, Never>?

    init(copying url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Knittany-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        pdf = folder.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.copyItem(at: url, to: pdf)
    }

    var fileName: String { pdf.lastPathComponent }

    func read(_ method: ImportDraft.Method) {
        phase = .reading(method)
        received = 0
        let pdf = pdf
        task = Task {
            do {
                let draft: ImportDraft
                switch method {
                case .offline:
                    draft = try await Task.detached { try OfflineReader.read(pdf) }.value
                case .claude:
                    guard let key = APIKeyStore.key else { throw PatternError("Add an Anthropic API key in Settings first.") }
                    draft = try await ClaudeReader(apiKey: key).read(pdf) { count in
                        Task { @MainActor in self.received = count }
                    }
                }
                guard !Task.isCancelled else { return }
                self.draft = draft
                phase = .reviewing
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed("\(error)")
            }
        }
    }

    func cancelReading() {
        task?.cancel()
        task = nil
        phase = .choosing
    }

    func discard() {
        task?.cancel()
        try? FileManager.default.removeItem(at: pdf.deletingLastPathComponent())
    }
}

struct PDFImportSheet: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: PDFImport

    var body: some View {
        Group {
            switch session.phase {
            case .choosing:
                chooser
            case .reading(let method):
                VStack(spacing: 14) {
                    ProgressView()
                    Text(method == .claude ? "Claude is reading \(session.fileName)…" : "Reading \(session.fileName)…").scaledFont(.headline)
                    if method == .claude {
                        Text(session.received == 0 ? "This usually takes a minute or two." : "\(session.received.formatted()) characters received")
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                    Button("Cancel") { session.cancelReading() }
                }
                .frame(width: 460, height: 220)
            case .reviewing:
                if let draft = Binding($session.draft) {
                    ImportReviewView(draft: draft, pdf: session.pdf) {
                        close()
                    } save: { pattern in
                        model.savePattern(pattern, sourcePDF: session.pdf)
                        close()
                    }
                }
            case .failed(let message):
                VStack(alignment: .leading, spacing: 12) {
                    Label("Couldn't read \(session.fileName)", systemImage: "exclamationmark.triangle.fill").scaledFont(.headline)
                    ScrollView { Text(message).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(maxHeight: 160)
                    HStack {
                        Spacer()
                        Button("Close") { close() }
                        Button("Try Again") { session.phase = .choosing }.keyboardShortcut(.defaultAction)
                    }
                }
                .padding(20)
                .frame(width: 480)
            }
        }
    }

    var chooser: some View {
        let hasKey = APIKeyStore.hasKey
        return VStack(alignment: .leading, spacing: 16) {
            Text("Import \(session.fileName)").scaledFont(.headline)
            Text("The pattern is read into a draft: its sizes, gauge, finished measurements, and every number that changes with size. You check and correct the draft before it's saved.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Read on this Mac").bold()
                            Text("Nothing leaves your computer. Works best with text PDFs laid out like most patterns.")
                                .scaledFont(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button("Read") { session.read(.offline) }.keyboardShortcut(.defaultAction)
                    }
                    Divider()
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Read with Claude").bold()
                            Text(hasKey
                                 ? "Sends the PDF to Anthropic. Better with unusual layouts, size tables and schematics."
                                 : "Add an Anthropic API key in Settings (⌘,) to use this.")
                                .scaledFont(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button("Read with Claude") { session.read(.claude) }.disabled(!hasKey)
                    }
                }
                .padding(6)
            }
            HStack {
                Spacer()
                Button("Cancel") { close() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    func close() {
        session.discard()
        dismiss()
    }
}
