import SwiftUI

struct SettingsView: View {
    @State private var key = ""
    @State private var saved = APIKeyStore.hasKey
    @State private var problem: String?
    @AppStorage(TextSize.key) private var textSize = TextSize.standard

    var body: some View {
        Form {
            Section {
                Picker("Text size", selection: $textSize) {
                    ForEach(TextSize.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Reading")
            } footer: {
                Text("Makes the text bigger throughout Knittany, in Knit mode, and in the PDFs it exports. You can also use View > Bigger Text (⌘=) and Smaller Text (⌘−).")
                    .scaledFont(.caption).foregroundStyle(.secondary)
            }

            Section {
                SecureField("Anthropic API key", text: $key, prompt: Text(saved ? "Saved in your keychain" : "sk-ant-…"))
                HStack {
                    Button("Save Key") {
                        do {
                            try APIKeyStore.save(key)
                            saved = APIKeyStore.hasKey
                            key = ""
                            problem = nil
                        } catch {
                            problem = error.localizedDescription
                        }
                    }
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                    if saved {
                        Button("Remove Key", role: .destructive) {
                            try? APIKeyStore.save("")
                            saved = false
                        }
                    }
                }
                if let problem { Text(problem).foregroundStyle(.red) }
            } header: {
                Text("Reading PDFs with Claude")
            } footer: {
                Text("Optional. Patterns are read on this Mac unless you choose Claude when importing; then the PDF is sent to Anthropic, which handles messy layouts and charts better. Usage is billed to the key's Anthropic account. Get a key at console.anthropic.com.")
                    .scaledFont(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, idealWidth: 560)
        .padding(.vertical, 8)
    }
}
