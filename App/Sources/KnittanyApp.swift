import SwiftUI

@main
struct KnittanyApp: App {
    @State private var model = LibraryModel()

    var body: some Scene {
        WindowGroup("Knittany") {
            RootView()
                .environment(model)
                .scaledWindow()
                .frame(minWidth: 1000, minHeight: 640)
                // A PDF opened with the app goes to the open window, not a new one.
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        }
        .handlesExternalEvents(matching: ["*"])
        .commands {
            TextSizeCommands()
            CommandGroup(replacing: .newItem) {
                Button("New Person") { model.addPerson() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Import Pattern…") { model.choosingImport = true }
                    .keyboardShortcut("i", modifiers: .command)
                Button("Design a Sweater…") { model.newDesign() }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .scaledWindow()
        }
    }
}
