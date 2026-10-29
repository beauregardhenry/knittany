import KnitCore
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selection) {
                Section("Projects") {
                    ForEach(model.projects) { p in
                        Label(p.name, systemImage: "tshirt").tag(SidebarItem.project(p.id))
                    }
                    if model.projects.isEmpty {
                        Text("Open a pattern and choose New Project").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("People") {
                    ForEach(model.people) { p in
                        Label(p.name, systemImage: "person").tag(SidebarItem.person(p.id))
                    }
                    Button("Add Person", systemImage: "plus") { model.addPerson() }
                        .buttonStyle(.borderless)
                }
                Section("Patterns") {
                    ForEach(model.patterns) { p in
                        Label(p.name, systemImage: "doc.richtext").tag(SidebarItem.pattern(p.id))
                    }
                    Button("Import Pattern…", systemImage: "square.and.arrow.down") { model.choosingImport = true }
                        .buttonStyle(.borderless)
                    Button("Design a Sweater…", systemImage: "wand.and.stars") { model.newDesign() }
                        .buttonStyle(.borderless)
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240)
        } detail: {
            switch model.selection {
            case .project(let id):
                if let p = model.project(id) { ProjectView(project: p).id(id) }
            case .person(let id):
                if let p = model.person(id) { PersonView(person: p).id(id) }
            case .pattern(let id):
                if let e = model.entry(id) { PatternView(entry: e).id(id) }
            case nil:
                WelcomeView()
            }
        }
        .fileImporter(isPresented: $model.choosingImport, allowedContentTypes: [.pdf, .json]) { result in
            if case .success(let url) = result { model.importPattern(from: url) }
        }
        .onOpenURL { url in
            if url.isFileURL { model.importPattern(from: url) }
        }
        .onDrop(of: [.pdf, .fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL { Task { @MainActor in model.importPattern(from: url) } }
            }
            return true
        }
        .sheet(item: $model.designing) { session in
            DesignView(session: session)
        }
        .sheet(item: $model.pdfImport) { session in
            PDFImportSheet(session: session)
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("Knitting").font(.title)
            Text("1. Add the person you're knitting for and enter their measurements.\n2. Import a pattern PDF and check what was read, or design a sweater from scratch.\n3. Open the pattern and choose New Project.")
                .multilineTextAlignment(.leading)
                .foregroundStyle(.secondary)
        }
        .padding(40)
    }
}
