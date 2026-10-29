import SwiftUI

@main
struct KnittingApp: App {
    @State private var model = LibraryModel()

    var body: some Scene {
        WindowGroup("Knitting") {
            RootView()
                .environment(model)
                .frame(minWidth: 1000, minHeight: 640)
                // A PDF opened with the app goes to the open window, not a new one.
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        }
        .handlesExternalEvents(matching: ["*"])
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Person") { model.addPerson() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Import Pattern…") { model.choosingImport = true }
                    .keyboardShortcut("i", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
        }
    }
}
