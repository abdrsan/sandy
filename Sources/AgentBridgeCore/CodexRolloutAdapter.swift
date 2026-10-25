import Foundation

/// Состояние одной сессии Codex, нужное для разбора следующих строк rollout-а.
public struct CodexSessionState: Sendable {
    public var sessionID: String
    public var projectPath: String?
    /// Служебная нить (guardian, субагент): события не выдаются.
    public var isAuxiliary = false
    public var sawMeta = false
    public var lastUsage: AgentUsage?
    /// Последнее выданное состояние — для `disconnected` при пропаже файла.
    public var lastKind: AgentEventKind?

    public init(sessionID: String) {
        self.sessionID = sessionID
    }
}

/// Разбор строк `~/.codex/sessions/**/rollout-*.jsonl` в нормализованные события.
///
/// Читаются только типы записей и имена инструментов. Тексты сообщений,
/// рассуждения, аргументы и вывод команд не извлекаются.
public enum CodexRolloutAdapter {
    /// `rollout-2026-10-25T22-11-04-01a1740b-5fef-7ea1-bd04-6bc71f85b051.jsonl`
    /// → `01a1740b-5fef-7ea1-bd04-6bc71f85b051`.
    public static func sessionID(fromFileName name: String) -> String? {
        let stem = name.hasSuffix(".jsonl") ? String(name.dropLast(6)) : name
        guard stem.hasPrefix("rollout-"), stem.count >= 36 else { return nil }
        let candidate = String(stem.suffix(36))
        return UUID(uuidString: candidate) != nil ? candidate.lowercased() : nil
    }

    public static func events(
        line: JSONObject,
        state: inout CodexSessionState,
        fallbackKey: String,
        now: Date
    ) -> [AgentEvent] {
        let payload = line.object("payload") ?? [:]
        let timestamp = line.string("timestamp").flatMap(AgentTimestamp.parse) ?? now
        let key = line.int("ordinal").map(String.init) ?? fallbackKey
        let sessionID = state.sessionID
        let projectPath = state.projectPath

        func event(_ kind: AgentEventKind, operation: String? = nil, tool: String? = nil,
                   error: String? = nil, usage: AgentUsage? = nil) -> AgentEvent {
            AgentEvent(
                eventID: "codex:\(sessionID):\(key)", source: .codex, sessionID: sessionID,
                timestamp: timestamp, kind: kind, projectPath: projectPath,
                operation: operation, tool: tool, error: error, usage: usage)
        }

        var result: [AgentEvent] = []
        switch line.string("type") {
        case "session_meta":
            guard !state.sawMeta else { return [] }
            state.sawMeta = true
            if let id = Identifier.sanitized(payload.string("id")) { state.sessionID = id.lowercased() }
            state.projectPath = Identifier.path(payload.string("cwd")) ?? state.projectPath
            state.isAuxiliary = isAuxiliary(payload)
            var started = event(.sessionStarted)
            started.eventID = "codex:\(state.sessionID):\(key)"
            started.sessionID = state.sessionID
            started.projectPath = state.projectPath
            result = [started]

        case "turn_context":
            state.projectPath = Identifier.path(payload.string("cwd")) ?? state.projectPath

        case "event_msg":
            switch payload.string("type") {
            case "task_started", "turn_started":
                result = [event(.working)]
            case "task_complete", "turn_complete":
                result = [event(.turnCompleted)]
            case "turn_aborted":
                // Прерванный ход — не готовый ответ и не ошибка: агент стоит и
                // ждёт человека. Другие причины (`replaced`) сразу сменяются
                // новым ходом и отдельного состояния не дают.
                if payload.string("reason") == "interrupted" {
                    result = [event(.waiting, operation: OperationLabels.interrupted)]
                }
            case "token_count":
                if let total = payload.object("info")?.object("total_token_usage") {
                    let usage = AgentUsage(
                        inputTokens: total.int("input_tokens"),
                        outputTokens: total.int("output_tokens"),
                        cachedInputTokens: total.int("cached_input_tokens"))
                    if usage != state.lastUsage, usage.inputTokens != nil || usage.outputTokens != nil {
                        state.lastUsage = usage
                        result = [event(.usage, usage: usage)]
                    }
                }
            case "error":
                // Текущий Codex ошибки в rollout не пишет (EventMsg::Error не
                // сохраняется); ветка на случай, если начнёт. Текст не берём.
                let code = Identifier.sanitized(payload.string("codex_error_info"), maxLength: 64)
                result = [event(.failed, error: code ?? "error")]
            default:
                break
            }

        case "response_item":
            switch payload.string("type") {
            case "function_call", "custom_tool_call":
                let tool = OperationLabels.sanitizedToolName(payload.string("name"))
                // Блокирующий вопрос пользователю. `request_user_input_async`
                // не блокирует: ответ инструмента приходит сразу.
                let kind: AgentEventKind = tool == "request_user_input" ? .waiting : .working
                result = [event(kind, operation: OperationLabels.codex(tool: tool), tool: tool)]
            case "local_shell_call":
                result = [event(.working, operation: OperationLabels.runCommand, tool: "local_shell")]
            case "web_search_call":
                result = [event(.working, operation: OperationLabels.webSearch, tool: "web_search")]
            case "image_generation_call":
                result = [event(.working, operation: OperationLabels.image, tool: "image_generation")]
            default:
                break
            }

        default:
            break
        }

        if state.isAuxiliary { return [] }
        if let last = result.last(where: { $0.kind.isState }) { state.lastKind = last.kind }
        return result
    }

    /// Строка, не поместившаяся в предел длины. Тип записи и поля заголовка
    /// стоят в её начале, поэтому их можно достать из префикса.
    public static func events(
        oversizedPrefix prefix: Data,
        state: inout CodexSessionState,
        fallbackKey: String,
        now: Date
    ) -> [AgentEvent] {
        let text = String(decoding: prefix, as: UTF8.self)
        let types = JSONSupport.sniffStrings("type", in: text)
        guard let top = types.first else { return [] }
        var line: JSONObject = ["type": top]
        if let stamp = JSONSupport.sniffString("timestamp", in: text) { line["timestamp"] = stamp }
        if let ordinal = JSONSupport.sniffLastInt("ordinal", in: String(text.prefix(200))) {
            line["ordinal"] = ordinal
        }
        var payload: JSONObject = [:]
        if types.count > 1 { payload["type"] = types[1] }
        switch top {
        case "session_meta":
            payload["id"] = JSONSupport.sniffString("id", in: text)
            payload["cwd"] = JSONSupport.sniffString("cwd", in: text)
            payload["thread_source"] = JSONSupport.sniffString("thread_source", in: text)
            if text.contains("\"subagent\"") { payload["source"] = ["subagent": [:] as JSONObject] }
        case "turn_context":
            payload["cwd"] = JSONSupport.sniffString("cwd", in: text)
        case "event_msg":
            payload["reason"] = JSONSupport.sniffString("reason", in: text)
        case "response_item":
            payload["name"] = JSONSupport.sniffString("name", in: text)
        default:
            break
        }
        line["payload"] = payload
        return events(line: line, state: &state, fallbackKey: fallbackKey, now: now)
    }

    static func isAuxiliary(_ meta: JSONObject) -> Bool {
        if let source = meta.object("source"), source["subagent"] != nil { return true }
        switch meta.string("thread_source") {
        case "guardian_review", "subagent": return true
        default: return false
        }
    }
}
