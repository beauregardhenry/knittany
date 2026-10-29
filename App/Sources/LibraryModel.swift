import Foundation
import KnitCore
import Observation

enum SidebarItem: Hashable {
    case project(UUID)
    case person(UUID)
    case pattern(UUID)
}

/// The app's state: everything in the library folder, saved after each change.
@MainActor
@Observable
final class LibraryModel {
    let store: LibraryStore
    private(set) var index = LibraryIndex()
    var selection: SidebarItem?
    var errorMessage: String?
    /// Shows the open panel for importing a pattern (File > Import Pattern…).
    var choosingImport = false
    /// A pattern PDF being read and reviewed.
    var pdfImport: PDFImport?
    private var patternCache: [UUID: KnitCore.Pattern] = [:]

    /// `KNITTING_LIBRARY` points the app at another folder, for testing.
    static var defaultStore: LibraryStore {
        let path = ProcessInfo.processInfo.environment["KNITTING_LIBRARY"]
        return LibraryStore(root: path.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? LibraryStore.defaultRoot)
    }

    init(store: LibraryStore = LibraryModel.defaultStore) {
        self.store = store
        do {
            index = try store.load()
        } catch {
            errorMessage = "Couldn't read the library: \(error)"
        }
    }

    private func save() {
        do {
            try store.save(index)
        } catch {
            errorMessage = "Couldn't save: \(error)"
        }
    }

    // MARK: People

    var people: [Person] { index.people.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }

    func person(_ id: UUID?) -> Person? {
        id.flatMap { id in index.people.first { $0.id == id } }
    }

    func addPerson() {
        let p = Person(name: "New person", units: Locale.current.measurementSystem == .us ? .inchFirst : .cmFirst)
        index.people.append(p)
        save()
        selection = .person(p.id)
    }

    func update(_ person: Person) {
        guard let i = index.people.firstIndex(where: { $0.id == person.id }), index.people[i] != person else { return }
        index.people[i] = person
        save()
    }

    func deletePerson(_ id: UUID) {
        index.people.removeAll { $0.id == id }
        for i in index.projects.indices where index.projects[i].personID == id {
            index.projects[i].personID = nil
        }
        if selection == .person(id) { selection = nil }
        save()
    }

    // MARK: Patterns

    var patterns: [PatternEntry] { index.patterns.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }

    func entry(_ id: UUID) -> PatternEntry? { index.patterns.first { $0.id == id } }

    func pattern(_ id: UUID) -> KnitCore.Pattern? {
        if let p = patternCache[id] { return p }
        do {
            let p = try store.pattern(id)
            patternCache[id] = p
            return p
        } catch {
            errorMessage = "Couldn't read the pattern: \(error)"
            return nil
        }
    }

    /// A PDF starts the read-and-review flow; a pattern file goes straight in.
    func importPattern(from url: URL) {
        if url.pathExtension.lowercased() == "pdf" {
            do {
                pdfImport = try PDFImport(copying: url)
            } catch {
                errorMessage = "Couldn't open \(url.lastPathComponent): \(error)"
            }
            return
        }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let entry = try store.importPattern(from: url, into: &index)
            selection = .pattern(entry.id)
        } catch {
            errorMessage = "Couldn't import \(url.lastPathComponent): \(error)"
        }
    }

    func savePattern(_ pattern: KnitCore.Pattern, sourcePDF: URL?) {
        do {
            let entry = try store.importPattern(pattern, sourcePDF: sourcePDF, into: &index)
            selection = .pattern(entry.id)
        } catch {
            errorMessage = "Couldn't save \(pattern.name): \(error)"
        }
    }

    func attachSourcePDF(_ url: URL, to id: UUID) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            try store.attachSourcePDF(url, to: id, in: &index)
        } catch {
            errorMessage = "Couldn't attach \(url.lastPathComponent): \(error)"
        }
    }

    func sourcePDF(_ id: UUID) -> URL? {
        entry(id)?.hasSourcePDF == true ? store.sourcePDFURL(id) : nil
    }

    func deletePattern(_ id: UUID) {
        do {
            try store.deletePattern(id, from: &index)
            patternCache[id] = nil
            selection = nil
        } catch {
            errorMessage = "Couldn't delete the pattern: \(error)"
        }
    }

    // MARK: Projects

    var projects: [Project] { index.projects.sorted { $0.createdAt > $1.createdAt } }

    func project(_ id: UUID) -> Project? { index.projects.first { $0.id == id } }

    func addProject(patternID: UUID, personID: UUID? = nil) {
        let name = [person(personID)?.name, entry(patternID)?.name].compactMap { $0 }.joined(separator: "'s ")
        let units = person(personID)?.units ?? .cmFirst
        let p = Project(name: name.isEmpty ? "New project" : name, patternID: patternID, personID: personID ?? index.people.first?.id, units: units)
        index.projects.append(p)
        save()
        selection = .project(p.id)
    }

    func update(_ project: Project) {
        guard let i = index.projects.firstIndex(where: { $0.id == project.id }), index.projects[i] != project else { return }
        index.projects[i] = project
        save()
    }

    func deleteProject(_ id: UUID) {
        index.projects.removeAll { $0.id == id }
        if selection == .project(id) { selection = nil }
        save()
    }
}
