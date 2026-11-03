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
                if !model.favorites.isEmpty {
                    Section {
                        ForEach(model.favorites) { p in
                            SidebarRow(title: p.name, icon: "star.fill", colour: Yarn.yellow).tag(SidebarItem.favorite(p.id))
                                .contextMenu { favoriteButton(p) }
                        }
                    } header: {
                        SidebarHeader(title: "Favorites", colour: Yarn.yellow)
                    }
                }
                Section {
                    ForEach(model.projects) { p in
                        SidebarRow(title: p.name, icon: "tshirt", colour: Yarn.orange).tag(SidebarItem.project(p.id))
                    }
                    if model.projects.isEmpty {
                        Text("Open a pattern and choose New Project").scaledFont(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    SidebarHeader(title: "Projects", colour: Yarn.orange)
                }
                Section {
                    ForEach(model.people) { p in
                        SidebarRow(title: p.name, icon: "person", colour: Yarn.pink).tag(SidebarItem.person(p.id))
                    }
                    Button { model.addPerson() } label: { SidebarRow(title: "Add Person", icon: "plus.circle.fill", colour: Yarn.pink) }
                        .buttonStyle(.plain)
                } header: {
                    SidebarHeader(title: "People", colour: Yarn.pink)
                }
                Section {
                    ForEach(model.patterns) { p in
                        SidebarRow(title: p.name, icon: "doc.richtext", colour: Yarn.purple, starred: p.favorite).tag(SidebarItem.pattern(p.id))
                            .contextMenu { favoriteButton(p) }
                    }
                    Button { model.choosingImport = true } label: { SidebarRow(title: "Import Pattern…", icon: "square.and.arrow.down.fill", colour: Yarn.leaf) }
                        .buttonStyle(.plain)
                    Button { model.newDesign() } label: { SidebarRow(title: "Design a Sweater…", icon: "wand.and.stars", colour: Yarn.green) }
                        .buttonStyle(.plain)
                } header: {
                    SidebarHeader(title: "Patterns", colour: Yarn.purple)
                }
            }
            .navigationSplitViewColumnWidth(min: sidebarWidth, ideal: sidebarWidth + 40)
        } detail: {
            switch model.selection {
            case .project(let id):
                if let p = model.project(id) { ProjectView(project: p).id(id) }
            case .person(let id):
                if let p = model.person(id) { PersonView(person: p).id(id) }
            case .pattern(let id), .favorite(let id):
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

extension RootView {
    func favoriteButton(_ p: PatternEntry) -> some View {
        Button(p.favorite ? "Remove from Favorites" : "Add to Favorites", systemImage: p.favorite ? "star.slash" : "star") {
            model.setFavorite(!p.favorite, for: p.id)
        }
    }
}

/// A sidebar row at the chosen text size. Sidebars set their own size on
/// ordinary labels, so the row's text and icon are sized here instead.
struct SidebarRow: View {
    let title: String
    let icon: String
    var colour = Color.accentColor
    var starred = false
    @AppStorage(TextSize.key) private var size = TextSize.standard

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: size.points(.body) * 0.95))
                .foregroundStyle(colour)
                .frame(width: size.points(.body) * 1.4)
            // Explicit, so rows that are buttons don't draw their text in black.
            Text(title)
                .font(.system(size: size.points(.body)))
                .foregroundStyle(.primary)
                .lineLimit(2)
            if starred {
                Spacer(minLength: 4)
                Image(systemName: "star.fill")
                    .font(.system(size: size.points(.caption)))
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("Favorite")
            }
        }
        .padding(.vertical, size == .standard ? 0 : 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// A sidebar section title with a dot of its colour.
struct SidebarHeader: View {
    let title: String
    let colour: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(colour).frame(width: 8, height: 8)
            Text(title).scaledFont(.subheadline, bold: true)
        }
    }
}
