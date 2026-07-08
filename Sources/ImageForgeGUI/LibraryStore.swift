import Foundation

/// One named library: a folder where generations are written and browsed. `path`
/// is a plain filesystem path (the app is Developer-ID direct, not sandboxed, so
/// no security-scoped bookmark is needed).
struct Library: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var path: String
}

/// Owns the ordered list of libraries and which one is active, persisted as JSON
/// (`libraries.json`). On first run it seeds a **"Default"** library pointing at
/// the app's original fixed library dir, so images generated before this feature
/// keep working (migration). The JSON path and default dir are injectable so tests
/// use a temp file.
///
/// Not `@MainActor`: it's owned and mutated only by `AppModel` (which is), so it
/// never sees concurrent access.
final class LibraryStore {
    private let fileURL: URL
    private let defaultLibraryDir: URL

    private(set) var libraries: [Library]
    private(set) var activeID: Library.ID

    init(fileURL: URL, defaultLibraryDir: URL) {
        self.fileURL = fileURL
        self.defaultLibraryDir = defaultLibraryDir

        if let loaded = Self.load(from: fileURL), !loaded.libraries.isEmpty {
            libraries = loaded.libraries
            activeID = loaded.libraries.contains(where: { $0.id == loaded.active })
                ? loaded.active : loaded.libraries[0].id
        } else {
            let def = Library(id: UUID(), name: "Default", path: defaultLibraryDir.path)
            libraries = [def]
            activeID = def.id
            persist()
        }
    }

    /// The active library (always present — the list is never empty).
    var active: Library {
        libraries.first { $0.id == activeID } ?? libraries[0]
    }

    /// The protected "Default" library: the first (migrated) entry. Adds append,
    /// and it's never removable, so the first entry stays the Default.
    var defaultID: Library.ID? { libraries.first?.id }

    /// A library is removable only when it isn't the Default and isn't the last one.
    func canRemove(_ id: Library.ID) -> Bool {
        libraries.count > 1 && id != defaultID
    }

    /// Add a library for `url`. Re-adding an existing path returns the existing
    /// entry rather than duplicating it. Does not change the active library.
    @discardableResult
    func add(name: String, url: URL) -> Library {
        if let existing = libraries.first(where: { $0.path == url.path }) {
            return existing
        }
        let lib = Library(id: UUID(), name: name, path: url.path)
        libraries.append(lib)
        persist()
        return lib
    }

    /// Remove a library. Refuses the Default and the last remaining library
    /// (returns false). If the active library is removed, the Default becomes
    /// active.
    @discardableResult
    func remove(_ id: Library.ID) -> Bool {
        guard canRemove(id) else { return false }
        libraries.removeAll { $0.id == id }
        if activeID == id { activeID = libraries[0].id }
        persist()
        return true
    }

    /// Make `id` the active library (no-op for an unknown id).
    func setActive(_ id: Library.ID) {
        guard libraries.contains(where: { $0.id == id }) else { return }
        activeID = id
        persist()
    }

    // MARK: - Persistence

    private struct Persisted: Codable {
        var libraries: [Library]
        var active: Library.ID
    }

    private func persist() {
        let payload = Persisted(libraries: libraries, active: activeID)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) -> Persisted? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Persisted.self, from: data)
    }

    /// The default on-disk location:
    /// `~/Library/Application Support/image-forge-gui/libraries.json`.
    static func defaultStoreURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent("image-forge-gui/libraries.json")
    }
}
