import Foundation
import Testing
@testable import Sandy

/// An unreadable `notes.json` must never be replaced by the empty list the
/// store falls back to. Each test works in its own temporary folder.
@MainActor
struct NoteStoreTests {
    private func folder() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sandy-notes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func unreadableFileIsKeptAsideBeforeAnyWrite() throws {
        let dir = try folder()
        let file = dir.appendingPathComponent("notes.json")
        let broken = Data("[{\"id\":\"not-a-uuid\",\"text\":\"phone 555-0100\"".utf8)
        try broken.write(to: file)

        let store = NoteStore(file: file)
        #expect(store.notes.isEmpty)
        store.add()
        store.update(try #require(store.selected), text: "new")
        store.flush()

        let kept = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("notes.unreadable-") }
        #expect(kept.count == 1)
        #expect(try Data(contentsOf: dir.appendingPathComponent(kept[0])) == broken)
        #expect(NoteStore(file: file).notes.map(\.text) == ["new"])
    }

    @Test func validFileRoundTrips() throws {
        let file = try folder().appendingPathComponent("notes.json")
        let store = NoteStore(file: file)
        store.add()
        store.update(try #require(store.selected), text: "hello")
        store.flush()
        #expect(NoteStore(file: file).notes.map(\.text) == ["hello"])
    }
}
