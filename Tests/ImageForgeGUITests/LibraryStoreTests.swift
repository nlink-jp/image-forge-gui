import XCTest
@testable import ImageForgeGUI

/// LibraryStore: seeding/migration, add/switch/remove, protection of the
/// Default/last library, and JSON round-tripping through an injected temp file.
final class LibraryStoreTests: XCTestCase {
    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ifgui-libstore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    private func storeURL() -> URL { tmpDir.appendingPathComponent("libraries.json") }
    private func defaultDir() -> URL { tmpDir.appendingPathComponent("library") }

    private func makeStore() -> LibraryStore {
        LibraryStore(fileURL: storeURL(), defaultLibraryDir: defaultDir())
    }

    /// A fresh store seeds exactly one "Default" library pointing at the migration
    /// dir, active, and not removable.
    func testSeedsDefaultLibrary() {
        let store = makeStore()
        XCTAssertEqual(store.libraries.count, 1)
        XCTAssertEqual(store.libraries[0].name, "Default")
        XCTAssertEqual(store.libraries[0].path, defaultDir().path)
        XCTAssertEqual(store.activeID, store.libraries[0].id)
        XCTAssertFalse(store.canRemove(store.libraries[0].id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL().path),
                      "seeding must persist libraries.json")
    }

    /// Add + switch + remove survive a reload from the same file.
    func testAddSwitchRemoveRoundTripThroughFile() {
        let added: Library
        do {
            let store = makeStore()
            added = store.add(name: "Project A", url: tmpDir.appendingPathComponent("proj-a"))
            store.setActive(added.id)
            XCTAssertEqual(store.libraries.count, 2)
            XCTAssertEqual(store.activeID, added.id)
        }

        // Reload: the second library and the active selection are persisted.
        do {
            let reloaded = makeStore()
            XCTAssertEqual(reloaded.libraries.count, 2)
            XCTAssertEqual(reloaded.activeID, added.id)
            XCTAssertEqual(reloaded.libraries[1].name, "Project A")

            XCTAssertTrue(reloaded.canRemove(added.id))
            XCTAssertTrue(reloaded.remove(added.id))
            XCTAssertEqual(reloaded.libraries.count, 1)
            // Removing the active library falls back to the Default.
            XCTAssertEqual(reloaded.activeID, reloaded.libraries[0].id)
        }

        // The removal persisted too.
        let final = makeStore()
        XCTAssertEqual(final.libraries.count, 1)
        XCTAssertEqual(final.libraries[0].name, "Default")
    }

    /// The Default / last library can never be removed.
    func testCannotRemoveDefaultOrLast() {
        let store = makeStore()
        let defaultID = store.libraries[0].id
        XCTAssertFalse(store.remove(defaultID))
        XCTAssertEqual(store.libraries.count, 1)

        // Even with a second library, the Default stays protected.
        let other = store.add(name: "Other", url: tmpDir.appendingPathComponent("other"))
        XCTAssertFalse(store.canRemove(defaultID))
        XCTAssertFalse(store.remove(defaultID))
        // The non-default one is removable.
        XCTAssertTrue(store.canRemove(other.id))
    }

    /// Re-adding the same path returns the existing entry instead of duplicating.
    func testAddIsIdempotentOnPath() {
        let store = makeStore()
        let url = tmpDir.appendingPathComponent("dup")
        let first = store.add(name: "Dup", url: url)
        let second = store.add(name: "Dup Again", url: url)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(store.libraries.count, 2)
    }

    /// setActive ignores an unknown id (no crash, unchanged active).
    func testSetActiveIgnoresUnknownID() {
        let store = makeStore()
        let original = store.activeID
        store.setActive(UUID())
        XCTAssertEqual(store.activeID, original)
    }
}
