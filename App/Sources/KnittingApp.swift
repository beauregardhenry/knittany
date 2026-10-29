import SwiftUI

@main
struct KnittingApp: App {
    @State private var model = LibraryModel()

    var body: some Scene {
        WindowGroup("Knitting") {
            RootView()
                .environment(model)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Person") { model.addPerson() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }
    }
}
