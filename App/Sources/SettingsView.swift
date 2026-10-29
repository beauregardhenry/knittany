import SwiftUI

struct SettingsView: View {
    @State private var key = ""
    @State private var saved = APIKeyStore.key != nil
    @State private var problem: String?

    var body: some View {
        Form {
            Section {
                SecureField("Anthropic API key", text: $key, prompt: Text(saved ? "Saved in your keychain" : "sk-ant-…"))
                HStack {
                    Button("Save Key") {
                        do {
                            try APIKeyStore.save(key)
                            saved = APIKeyStore.key != nil
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
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding(.vertical, 8)
    }
}
