import Foundation
import Testing
@testable import Sandy

struct AgentEventTests {
    private func line(_ changes: [String: Any] = [:]) throws -> Data {
        var value: [String: Any] = [
            "schema_version": 1, "event_id": "event-1", "source": "codex",
            "session_id": "session-1", "timestamp": "2026-10-25T18:00:00.000Z", "kind": "working"
        ]
        value.merge(changes) { _, new in new }
        return try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }

    @Test func bothISO8601PrecisionsAndUnknownFieldsDecode() throws {
        let withMilliseconds = try JSONDecoder().decode(AgentEvent.self, from: line([
            "project_path": "/Users/test/project", "operation": "Read file",
            "prompt": "must not be retained", "usage": ["input_tokens": 123, "output_tokens": NSNull()]
        ]))
        let without = try JSONDecoder().decode(AgentEvent.self, from: line(["timestamp": "2026-10-25T18:00:00Z"]))
        #expect(withMilliseconds.timestamp == without.timestamp)
        #expect(withMilliseconds.usage == AgentUsage(inputTokens: 123))
        #expect(withMilliseconds.projectPath == "/Users/test/project")
        #expect(withMilliseconds.operation == "Read file")
    }

    @Test func invalidEnvelopeAndUsageAreRejected() throws {
        let changes: [[String: Any]] = [
            ["schema_version": 2], ["event_id": ""], ["session_id": "  "],
            ["event_id": String(repeating: "x", count: 513)], ["session_id": "bad\u{0}id"],
            ["timestamp": "not a date"], ["source": "other"], ["kind": "other"],
            ["usage": ["input_tokens": -1]], ["usage": ["output_tokens": -1]]
        ]
        for change in changes {
            var decoder = AgentJSONLDecoder()
            #expect(decoder.append(try line(change) + Data([0x0A])).isEmpty)
            #expect(decoder.rejectedLines == 1)
        }
    }

    @Test func pathsAndOperationsAreBoundedMetadata() throws {
        let event = try JSONDecoder().decode(AgentEvent.self, from: line([
            "project_path": "relative/path", "operation": "  Read\nfile\t" + String(repeating: "a", count: 500)
        ]))
        #expect(event.projectPath == nil)
        #expect(event.operation?.count == 160)
        #expect(event.operation?.contains("\n") == false)
        #expect(event.operation?.contains("\t") == false)
        let oversizedPath = try JSONDecoder().decode(AgentEvent.self, from: line(["project_path": "/" + String(repeating: "x", count: 4_096)]))
        #expect(oversizedPath.projectPath == nil)
    }

    @Test func splitUTF8CRLFAndFinalLineAreFramed() throws {
        let bytes = try line(["operation": "Чтение файлов"])
        // Every possible byte boundary includes boundaries inside Cyrillic UTF-8.
        for split in 0...bytes.count {
            var decoder = AgentJSONLDecoder()
            #expect(decoder.append(Data(bytes.prefix(split))).isEmpty)
            let events = decoder.append(Data(bytes.dropFirst(split)) + Data([0x0D, 0x0A]))
            #expect(events.count == 1)
            #expect(events.first?.operation == "Чтение файлов")
            #expect(decoder.rejectedLines == 0)
            #expect(decoder.finish().isEmpty)
        }
        var decoder = AgentJSONLDecoder()
        #expect(decoder.append(bytes).isEmpty)
        #expect(decoder.finish().count == 1)
        #expect(decoder.finish().isEmpty)
    }

    @Test func oversizedMalformedAndPartialLinesDoNotPoisonFollowingEvents() throws {
        var decoder = AgentJSONLDecoder()
        #expect(decoder.append(Data(repeating: 0x61, count: 70_000)).isEmpty)
        #expect(decoder.rejectedLines == 1)
        #expect(decoder.append(Data(repeating: 0x61, count: 70_000)).isEmpty)
        #expect(decoder.rejectedLines == 1)
        let stream = Data("\n{bad json}\n\n".utf8) + (try line()) + Data([0x0A])
        #expect(decoder.append(stream).count == 1)
        #expect(decoder.rejectedLines == 2)
        #expect(decoder.append(Data([0xC3])).isEmpty)
        #expect(decoder.finish().isEmpty)
        #expect(decoder.rejectedLines == 3)
    }
}
