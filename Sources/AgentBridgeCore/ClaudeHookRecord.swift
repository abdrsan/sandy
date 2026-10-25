import Foundation

/// То, что `sandy-agent claude-hook` оставляет от payload-а Claude Code.
///
/// Белый список полей. Промпт, `tool_input`, `tool_response`,
/// `last_assistant_message`, текст уведомления и `error_details` не
/// копируются никогда: их нет в этой структуре.
public struct ClaudeHookRecord: Codable, Equatable, Sendable {
    public var version = 1
    public var eventID: String
    public var receivedAt: Date
    public var hookEvent: String
    public var sessionID: String
    public var cwd: String?
    public var toolName: String?
    public var notificationType: String?
    public var errorType: String?
    /// `source` из SessionStart: startup, resume, clear, compact, fork.
    public var startSource: String?
    /// `reason` из SessionEnd.
    public var endReason: String?
    public var isSubagent: Bool?
    /// Путь к журналу сессии — только чтобы монитор посчитал usage.
    public var transcriptPath: String?
    public var owner: ProcessIdentity?

    enum CodingKeys: String, CodingKey {
        case version = "v"
        case eventID = "id"
        case receivedAt = "at"
        case hookEvent = "hook"
        case sessionID = "session_id"
        case cwd
        case toolName = "tool"
        case notificationType = "notification"
        case errorType = "error"
        case startSource = "start"
        case endReason = "end"
        case isSubagent = "subagent"
        case transcriptPath = "transcript"
        case owner
    }

    public init(eventID: String, receivedAt: Date, hookEvent: String, sessionID: String) {
        self.eventID = eventID
        self.receivedAt = AgentTimestamp.truncatedToMilliseconds(receivedAt)
        self.hookEvent = hookEvent
        self.sessionID = sessionID
    }

    static let errorTypes: Set<String> = [
        "rate_limit", "overloaded", "authentication_failed", "oauth_org_not_allowed",
        "account_on_hold", "billing_error", "invalid_request", "model_not_found",
        "server_error", "max_output_tokens", "cloud_credential_error", "unknown"
    ]

    /// Payload хука → запись. nil, если это не событие Claude Code.
    public static func make(
        payload data: Data,
        now: Date,
        owner: ProcessIdentity?,
        randomID: () -> String = { UUID().uuidString.lowercased() }
    ) -> ClaudeHookRecord? {
        let payload: JSONObject
        if let object = JSONSupport.object(from: data) {
            payload = object
        } else {
            // Огромный payload (Write с большим файлом) мог не разобраться —
            // нужные поля короткие и стоят в начале.
            let text = String(decoding: data.prefix(64 << 10), as: UTF8.self)
            let keys = ["session_id", "hook_event_name", "cwd", "transcript_path", "tool_name"]
            payload = Dictionary(uniqueKeysWithValues: keys.compactMap { key in
                JSONSupport.sniffString(key, in: text).map { (key, $0 as Any) }
            })
        }
        guard let session = Identifier.sanitized(payload.string("session_id")),
              let hook = Identifier.sanitized(payload.string("hook_event_name"), maxLength: 40)
        else { return nil }

        let millis = Int64((now.timeIntervalSince1970 * 1000).rounded(.down))
        var record = ClaudeHookRecord(
            eventID: "claude:\(session):\(millis):\(hook):\(randomID().prefix(12))",
            receivedAt: now, hookEvent: hook, sessionID: session)
        record.cwd = Identifier.path(payload.string("cwd"))
        record.toolName = OperationLabels.sanitizedToolName(payload.string("tool_name"))
        record.notificationType = Identifier.sanitized(payload.string("notification_type"), maxLength: 64)
        if let error = payload.string("error") {
            record.errorType = errorTypes.contains(error) ? error : "unknown"
        }
        record.startSource = hook == "SessionStart" ? Identifier.sanitized(payload.string("source"), maxLength: 32) : nil
        record.endReason = hook == "SessionEnd" ? Identifier.sanitized(payload.string("reason"), maxLength: 64) : nil
        if payload.string("agent_id") != nil { record.isSubagent = true }
        if let path = Identifier.path(payload.string("transcript_path")), path.hasSuffix(".jsonl") {
            record.transcriptPath = path
        }
        record.owner = owner
        return record
    }

    public func jsonLine() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(AgentTimestamp.format(date))
        }
        return (try? encoder.encode(self)) ?? Data()
    }

    public static func decode(_ data: Data) -> ClaudeHookRecord? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            guard let date = AgentTimestamp.parse(try c.decode(String.self)) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "bad date")
            }
            return date
        }
        return try? decoder.decode(ClaudeHookRecord.self, from: data)
    }
}

/// Запись хука → нормализованные события.
public enum ClaudeHookAdapter {
    /// Уведомления, означающие «агент ждёт человека».
    static let waitingNotifications: Set<String> = [
        "permission_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input"
    ]

    public static func events(for record: ClaudeHookRecord, lastKind: AgentEventKind?) -> [AgentEvent] {
        func event(_ kind: AgentEventKind, operation: String? = nil, tool: String? = nil,
                   error: String? = nil) -> AgentEvent {
            AgentEvent(
                eventID: record.eventID, source: .claude, sessionID: record.sessionID,
                timestamp: record.receivedAt, kind: kind, projectPath: record.cwd,
                operation: operation, tool: tool, error: error)
        }
        let tool = record.toolName
        switch record.hookEvent {
        case "SessionStart":
            // compact — та же сессия после сжатия контекста, не новое начало.
            return record.startSource == "compact" ? [] : [event(.sessionStarted)]
        case "UserPromptSubmit":
            return [event(.working)]
        case "PreToolUse":
            return [event(.working, operation: OperationLabels.claude(tool: tool), tool: tool)]
        case "PostToolUse", "PostToolUseFailure":
            // Ошибка инструмента — не ошибка хода: агент продолжает работу.
            return [event(.working)]
        case "PermissionRequest":
            return [event(.waiting, operation: OperationLabels.claude(tool: tool), tool: tool)]
        case "PreCompact":
            return [event(.working, operation: OperationLabels.compaction)]
        case "Notification":
            guard let type = record.notificationType else { return [] }
            if waitingNotifications.contains(type) { return [event(.waiting)] }
            // Stop не приходит, если ход прервали; idle_prompt через минуту
            // тишины — единственный признак, что агент на самом деле стоит.
            if type == "idle_prompt", lastKind == .working { return [event(.waiting)] }
            return []
        case "Stop":
            return [event(.turnCompleted)]
        case "StopFailure":
            return [event(.failed, error: record.errorType ?? "unknown")]
        case "SessionEnd":
            return [event(.sessionEnded)]
        default:
            return []
        }
    }
}
