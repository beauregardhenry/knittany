import KnitCore
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(LibraryModel.self) private var model
    @AppStorage(TextSize.key) private var textSize = TextSize.standard

    /// Wide enough for pattern names at the chosen text size.
    var sidebarWidth: CGFloat { 220 * textSize.points(.body) / 13 }

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selection) {
                Section {
                    ForEach(model.projects) { p in
                        SidebarRow(title: p.name, icon: "tshirt").tag(SidebarItem.project(p.id))
                    }
                    if model.projects.isEmpty {
                        Text("Open a pattern and choose New Project").scaledFont(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Projects").scaledFont(.subheadline, bold: true)
                }
                Section {
                    ForEach(model.people) { p in
                        SidebarRow(title: p.name, icon: "person").tag(SidebarItem.person(p.id))
                    }
                    Button { model.addPerson() } label: { SidebarRow(title: "Add Person", icon: "plus") }
                        .buttonStyle(.borderless)
                } header: {
                    Text("People").scaledFont(.subheadline, bold: true)
                }
                Section {
                    ForEach(model.patterns) { p in
                        SidebarRow(title: p.name, icon: "doc.richtext").tag(SidebarItem.pattern(p.id))
                    }
                    Button { model.choosingImport = true } label: { SidebarRow(title: "Import Pattern…", icon: "square.and.arrow.down") }
                        .buttonStyle(.borderless)
                    Button { model.newDesign() } label: { SidebarRow(title: "Design a Sweater…", icon: "wand.and.stars") }
                        .buttonStyle(.borderless)
                } header: {
                    Text("Patterns").scaledFont(.subheadline, bold: true)
                }
            }
            .navigationSplitViewColumnWidth(min: sidebarWidth, ideal: sidebarWidth + 40)
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
                .scaledWindow()
        }
        .sheet(item: $model.pdfImport) { session in
            PDFImportSheet(session: session)
                .scaledWindow()
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

/// A sidebar row at the chosen text size. Sidebars set their own size on
/// ordinary labels, so the row's text and icon are sized here instead.
struct SidebarRow: View {
    let title: String
    let icon: String
    @AppStorage(TextSize.key) private var size = TextSize.standard

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: size.points(.body) * 0.95))
                .foregroundStyle(Color.accentColor)
                .frame(width: size.points(.body) * 1.4)
            Text(title)
                .font(.system(size: size.points(.body)))
                .lineLimit(2)
        }
        .padding(.vertical, size == .standard ? 0 : 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("Knittany").scaledFont(.title)
            Text("1. Add the person you're knitting for and enter their measurements.\n2. Import a pattern PDF and check what was read, or design a sweater from scratch.\n3. Open the pattern and choose New Project.")
                .multilineTextAlignment(.leading)
                .foregroundStyle(.secondary)
        }
        .padding(40)
    }
}
