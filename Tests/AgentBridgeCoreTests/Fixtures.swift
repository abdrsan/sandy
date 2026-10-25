import Foundation
@testable import AgentBridgeCore

/// Обезличенные фикстуры. Форма строк снята с настоящих rollout-ов Codex
/// 0.163 и payload-ов из документации Claude Code; все значения выдуманы.
/// Поля с «секретами» нужны, чтобы проверить, что они не утекают в события.
enum Fixture {
    static let secret = "SECRET-PROMPT-do-not-leak"
    static let secretCommand = "curl -H 'Authorization: Bearer sk-test-123' https://example.invalid"

    static func temporaryDirectory(_ name: String = #function) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sandy-agent-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func json(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Codex

    static func codexMeta(id: String, cwd: String, ordinal: Int = 0, subagent: Bool = false) -> String {
        var payload: [String: Any] = [
            "id": id, "session_id": id, "timestamp": "2026-10-25T17:00:00.000Z", "cwd": cwd,
            "originator": "Codex Desktop", "cli_version": "0.163.0-alpha.11.2",
            "base_instructions": ["text": secret],
            "thread_source": subagent ? "guardian_review" : "user"
        ]
        payload["source"] = subagent ? ["subagent": ["other": "guardian"]] as [String: Any] : "vscode" as Any
        return json(["timestamp": "2026-10-25T17:00:00.000Z", "ordinal": ordinal,
                     "type": "session_meta", "payload": payload])
    }

    static func codexEvent(_ type: String, ordinal: Int, extra: [String: Any] = [:],
                           at time: String = "2026-10-25T17:00:01.000Z") -> String {
        var payload: [String: Any] = ["type": type, "turn_id": "turn-1"]
        payload.merge(extra) { $1 }
        return json(["timestamp": time, "ordinal": ordinal, "type": "event_msg", "payload": payload])
    }

    static func codexToolCall(_ name: String, ordinal: Int, custom: Bool = true) -> String {
        var payload: [String: Any] = ["type": custom ? "custom_tool_call" : "function_call",
                                      "name": name, "call_id": "call-\(ordinal)", "status": "completed"]
        payload[custom ? "input" : "arguments"] = secretCommand
        return json(["timestamp": "2026-10-25T17:00:02.000Z", "ordinal": ordinal,
                     "type": "response_item", "payload": payload])
    }

    static func codexMessage(ordinal: Int) -> String {
        json(["timestamp": "2026-10-25T17:00:03.000Z", "ordinal": ordinal, "type": "response_item",
              "payload": ["type": "message", "role": "assistant",
                          "content": [["type": "output_text", "text": secret]]]])
    }

    static func codexTokens(ordinal: Int, input: Int, output: Int, cached: Int) -> String {
        codexEvent("token_count", ordinal: ordinal, extra: [
            "info": ["total_token_usage": ["input_tokens": input, "cached_input_tokens": cached,
                                           "output_tokens": output, "total_tokens": input + output],
                     "last_token_usage": ["input_tokens": 1, "output_tokens": 1]]
        ])
    }

    static func codexComplete(ordinal: Int) -> String {
        codexEvent("task_complete", ordinal: ordinal, extra: ["last_agent_message": secret])
    }

    /// По умолчанию — сегодняшний каталог, как у живой сессии.
    static func codexRollout(_ home: URL, id: String, day: String? = nil) -> URL {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let day = day ?? String(format: "%04d/%02d/%02d", parts.year!, parts.month!, parts.day!)
        let folder = home.appendingPathComponent("sessions/\(day)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("rollout-2026-10-25T17-00-00-\(id).jsonl")
    }

    // MARK: Claude

    static func claudePayload(_ hook: String, session: String, extra: [String: Any] = [:]) -> Data {
        var payload: [String: Any] = [
            "session_id": session, "hook_event_name": hook, "cwd": "/Users/tester/project-\(session)",
            "transcript_path": "/Users/tester/.claude/projects/x/\(session).jsonl",
            "permission_mode": "default", "prompt": secret,
            "tool_input": ["command": secretCommand], "last_assistant_message": secret
        ]
        payload.merge(extra) { $1 }
        return try! JSONSerialization.data(withJSONObject: payload)
    }

    static func claudeAssistantLine(id: String, input: Int, output: Int, cacheRead: Int = 0,
                                    cacheWrite: Int = 0, time: String = "2026-10-25T17:05:00.000Z") -> String {
        json([
            "type": "assistant", "timestamp": time, "isSidechain": false, "requestId": "req_\(id)",
            "message": ["id": id, "type": "message", "role": "assistant",
                        "content": [["type": "text", "text": secret]],
                        "usage": ["input_tokens": input, "output_tokens": output,
                                  "cache_read_input_tokens": cacheRead,
                                  "cache_creation_input_tokens": cacheWrite]]
        ])
    }
}

/// Сборщик вывода конвейера.
final class Collected {
    var events: [AgentEvent] = []
    lazy var pipeline = EventPipeline { [unowned self] in self.events.append($0) }

    var lines: String {
        events.map { String(decoding: $0.jsonLine(), as: UTF8.self) }.joined(separator: "\n")
    }

    func kinds(_ session: String) -> [AgentEventKind] {
        events.filter { $0.sessionID == session }.map(\.kind)
    }
}

extension URL {
    func write(_ lines: [String], append: Bool = false, newline: Bool = true) throws {
        var text = lines.joined(separator: "\n")
        if newline { text += "\n" }
        if append, let handle = try? FileHandle(forWritingTo: self) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try handle.close()
        } else {
            try Data(text.utf8).write(to: self)
        }
    }
}
