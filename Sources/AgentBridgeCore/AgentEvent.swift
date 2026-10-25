import Foundation

/// Откуда пришло событие.
public enum AgentSource: String, Codable, Sendable, CaseIterable {
    case claude
    case codex
}

/// Нормализованное состояние сессии. Значения — часть контракта с Sandy,
/// см. docs/agent-bridge.md.
public enum AgentEventKind: String, Codable, Sendable, CaseIterable {
    case sessionStarted = "session_started"
    case working
    case waiting
    /// Готовый ответ. Сессия при этом остаётся открытой.
    case turnCompleted = "turn_completed"
    case sessionEnded = "session_ended"
    case failed
    case usage
    /// Хелпер больше не может наблюдать сессию: процесс агента пропал или
    /// исчез файл журнала. Это не «успешно завершено».
    case disconnected

    /// События, которые меняют видимое состояние сессии (всё, кроме usage).
    public var isState: Bool { self != .usage }
}

/// Накопленные показатели всей сессии, не приращение. Неизвестное значение — nil.
public struct AgentUsage: Codable, Equatable, Sendable {
    /// Все входные токены, включая прочитанные из кэша.
    public var inputTokens: Int?
    public var outputTokens: Int?
    /// Часть `inputTokens`, прочитанная из кэша, если источник её сообщает.
    public var cachedInputTokens: Int?

    public init(inputTokens: Int?, outputTokens: Int?, cachedInputTokens: Int? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedInputTokens = cachedInputTokens
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cachedInputTokens = "cached_input_tokens"
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(inputTokens, forKey: .inputTokens)
        try c.encodeIfPresent(outputTokens, forKey: .outputTokens)
        try c.encodeIfPresent(cachedInputTokens, forKey: .cachedInputTokens)
    }
}

public struct AgentEvent: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    /// Стабилен между перезапусками хелпера: одно и то же исходное событие
    /// всегда получает один и тот же идентификатор.
    public var eventID: String
    public var source: AgentSource
    public var sessionID: String
    public var timestamp: Date
    public var kind: AgentEventKind
    public var projectPath: String?
    /// Короткое название действия для человека. Никогда не содержит аргументов.
    public var operation: String?
    /// Имя инструмента, как его называет агент (`Bash`, `exec`, `mcp__x__y`).
    public var tool: String?
    /// Код ошибки для `failed` (например `rate_limit`). Без текста ошибки.
    public var error: String?
    public var usage: AgentUsage?

    public init(
        eventID: String,
        source: AgentSource,
        sessionID: String,
        timestamp: Date,
        kind: AgentEventKind,
        projectPath: String? = nil,
        operation: String? = nil,
        tool: String? = nil,
        error: String? = nil,
        usage: AgentUsage? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.eventID = eventID
        self.source = source
        self.sessionID = sessionID
        self.timestamp = AgentTimestamp.truncatedToMilliseconds(timestamp)
        self.kind = kind
        self.projectPath = projectPath
        self.operation = operation
        self.tool = tool
        self.error = error
        self.usage = usage
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case eventID = "event_id"
        case source
        case sessionID = "session_id"
        case timestamp
        case kind
        case projectPath = "project_path"
        case operation
        case tool
        case error
        case usage
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        eventID = try c.decode(String.self, forKey: .eventID)
        source = try c.decode(AgentSource.self, forKey: .source)
        sessionID = try c.decode(String.self, forKey: .sessionID)
        let stamp = try c.decode(String.self, forKey: .timestamp)
        guard let date = AgentTimestamp.parse(stamp) else {
            throw DecodingError.dataCorruptedError(
                forKey: .timestamp, in: c, debugDescription: "bad timestamp")
        }
        timestamp = date
        kind = try c.decode(AgentEventKind.self, forKey: .kind)
        projectPath = try c.decodeIfPresent(String.self, forKey: .projectPath)
        operation = try c.decodeIfPresent(String.self, forKey: .operation)
        tool = try c.decodeIfPresent(String.self, forKey: .tool)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        usage = try c.decodeIfPresent(AgentUsage.self, forKey: .usage)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(eventID, forKey: .eventID)
        try c.encode(source, forKey: .source)
        try c.encode(sessionID, forKey: .sessionID)
        try c.encode(AgentTimestamp.format(timestamp), forKey: .timestamp)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(projectPath, forKey: .projectPath)
        try c.encodeIfPresent(operation, forKey: .operation)
        try c.encodeIfPresent(tool, forKey: .tool)
        try c.encodeIfPresent(error, forKey: .error)
        try c.encodeIfPresent(usage, forKey: .usage)
    }

    /// Одна строка JSONL без завершающего перевода строки.
    public func jsonLine() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // Кодирование собственной структуры из строк и чисел не падает.
        return (try? encoder.encode(self)) ?? Data()
    }
}

public enum AgentTimestamp {
    private static let fractional = Date.ISO8601FormatStyle(
        includingFractionalSeconds: true, timeZone: .gmt)
    private static let plain = Date.ISO8601FormatStyle(timeZone: .gmt)

    /// `2026-10-25T18:00:00.000Z`
    public static func format(_ date: Date) -> String {
        // Сам формат отбрасывает доли, а не округляет: 0.123 в Double —
        // это 0.12299…, и получалось бы .122.
        let millis = Int64((date.timeIntervalSince1970 * 1000).rounded())
        let seconds = millis.quotientAndRemainder(dividingBy: 1000)
        let (whole, fraction) = seconds.remainder < 0
            ? (seconds.quotient - 1, seconds.remainder + 1000) : (seconds.quotient, seconds.remainder)
        let base = plain.format(Date(timeIntervalSince1970: TimeInterval(whole)))
        return String(base.dropLast()) + "." + String(format: "%03lld", fraction) + "Z"
    }

    /// Принимает ISO 8601 с долями секунды любой длины или без них.
    public static func parse(_ string: String) -> Date? {
        if let date = try? fractional.parse(string) { return date }
        if let date = try? plain.parse(string) { return date }
        // Микросекунды и больше: оставляем три знака.
        guard let dot = string.firstIndex(of: "."),
              let zone = string[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" })
        else { return nil }
        let digits = string[string.index(after: dot)..<zone].prefix(3)
        return try? fractional.parse(String(string[..<dot]) + "." + digits + string[zone...])
    }

    static func truncatedToMilliseconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded() / 1000)
    }
}
