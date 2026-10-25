import AppKit
import Testing
@testable import Sandy

@MainActor
struct CalendarAndPersistenceTests {
    @Test func meetingLinksAcceptKnownHostsAndRejectLookalikes() throws {
        for value in ["https://meet.google.com/abc-defg-hij", "https://us02web.zoom.us/j/123", "https://teams.microsoft.com/l/meetup-join/123"] {
            #expect(MeetingLink.isJoinable(try #require(URL(string: value))))
        }
        for value in ["http://meet.google.com/abc", "https://meet.google.com.evil.example/abc", "https://evilzoom.us/j/123", "file:///tmp/test", "javascript:alert(1)"] {
            #expect(!MeetingLink.isJoinable(try #require(URL(string: value))))
        }
    }

    @Test func overlappingMeetingsAndTimeFormattingHandleBoundaries() {
        let now = Date()
        func meeting(_ id: String, _ start: Double, _ end: Double) -> CalendarStore.Meeting {
            .init(id: id, title: id, start: now.addingTimeInterval(start), end: now.addingTimeInterval(end),
                  calendarColor: .blue, link: nil, provider: nil)
        }
        #expect(meeting("a", 0, 60).overlaps(meeting("b", 30, 90)))
        #expect(!meeting("a", 0, 60).overlaps(meeting("b", 60, 90)))
        #expect(formatTime(125) == "2:05")
        #expect(formatTime(.infinity) == "--:--")
        #expect(formatTime(-1) == "--:--")
    }

    @Test func noteEditingCleanupAndSelectionSurviveReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sandy-notes-functions-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("notes.json")
        let notes = NoteStore(file: file)
        notes.add()
        let kept = try #require(notes.selected)
        notes.update(kept, text: "日本語のメモ")
        notes.add()
        notes.update(try #require(notes.selected), text: "  \n ")
        notes.leave()
        #expect(notes.notes.count == 1)
        #expect(notes.selected == kept)
        #expect(NoteStore(file: file).notes.first?.text == "日本語のメモ")
        notes.remove(kept)
        notes.flush()
        #expect(NoteStore(file: file).notes.isEmpty)
    }

    @Test func deferredWritesKeepOnlyNewestValueAndFlushOnlyOnce() {
        let writes = DebouncedWrite(after: 60)
        var saved: [String] = []
        writes.schedule { saved.append("old") }
        writes.schedule { saved.append("new") }
        writes.flush()
        writes.flush()
        #expect(saved == ["new"])
        writes.schedule { saved.append("cancelled") }
        writes.cancel()
        writes.flush()
        #expect(saved == ["new"])
    }
}
