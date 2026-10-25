import Foundation

enum AgentSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude, codex

    var id: String { rawValue }
    var title: String { self == .claude ? "Claude Code" : "Codex" }
}

struct AgentUsage: Codable, Equatable, Sendable {
    var inputTokens: Int?
    var outputTokens: Int?

    init(inputTokens: Int? = nil, outputTokens: Int? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }

    private enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens", outputTokens = "output_tokens"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = try values.decodeIfPresent(Int.self, forKey: .inputTokens)
        outputTokens = try values.decodeIfPresent(Int.self, forKey: .outputTokens)
        guard inputTokens.map({ $0 >= 0 }) ?? true,
              outputTokens.map({ $0 >= 0 }) ?? true else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Negative token count"))
        }
    }
}

/// Only the allowlisted metadata is decoded. The wire payload is never retained.
struct AgentEvent: Decodable, Sendable {
    enum Kind: String, Decodable, Sendable {
        case sessionStarted = "session_started"
        case working, waiting
        case turnCompleted = "turn_completed"
        case sessionEnded = "session_ended"
        case failed, usage, disconnected
    }

    var schemaVersion: Int
    var eventID: String
    var source: AgentSource
    var sessionID: String
    var timestamp: Date
    var kind: Kind
    var projectPath: String?
    var operation: String?
    var usage: AgentUsage?

    init(schemaVersion: Int = 1, eventID: String, source: AgentSource, sessionID: String,
         timestamp: Date, kind: Kind, projectPath: String? = nil, operation: String? = nil,
         usage: AgentUsage? = nil) {
        self.schemaVersion = schemaVersion
        self.eventID = eventID
        self.source = source
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.kind = kind
        self.projectPath = Self.safePath(projectPath)
        self.operation = Self.safeOperation(operation)
        self.usage = usage
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", eventID = "event_id", source
        case sessionID = "session_id", timestamp, kind
        case projectPath = "project_path", operation, usage
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        eventID = try values.decode(String.self, forKey: .eventID)
        source = try values.decode(AgentSource.self, forKey: .source)
        sessionID = try values.decode(String.self, forKey: .sessionID)
        guard schemaVersion == 1, Self.validID(eventID), Self.validID(sessionID) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid event envelope"))
        }
        let dateText = try values.decode(String.self, forKey: .timestamp)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateText) {
            timestamp = date
        } else {
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: dateText) else {
                throw DecodingError.dataCorruptedError(forKey: .timestamp, in: values, debugDescription: "Invalid ISO 8601 timestamp")
            }
            timestamp = date
        }
        kind = try values.decode(Kind.self, forKey: .kind)
        projectPath = Self.safePath(try values.decodeIfPresent(String.self, forKey: .projectPath))
        operation = Self.safeOperation(try values.decodeIfPresent(String.self, forKey: .operation))
        usage = try values.decodeIfPresent(AgentUsage.self, forKey: .usage)
    }

    private static func validID(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && value.utf8.count <= 512
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private static func safePath(_ value: String?) -> String? {
        guard let value, value.hasPrefix("/"), value.utf8.count <= 4_096,
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        return value
    }

    private static func safeOperation(_ value: String?) -> String? {
        guard let value else { return nil }
        let singleLine = value.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }.joined()
        let trimmed = singleLine.trimmingCharacters(in: .whitespacesAndNewlines)
        // Bound scalars as well as visible characters: one grapheme may contain
        // thousands of combining marks and otherwise bypass a character cap.
        return trimmed.isEmpty ? nil : String(String.UnicodeScalarView(trimmed.unicodeScalars.prefix(160)))
    }
}

/// Bounded byte framing preserves UTF-8 characters split across pipe reads.
struct AgentJSONLDecoder: Sendable {
    private static let maximumLineBytes = 64 * 1_024
    private var line = Data()
    private var discardingLine = false
    private(set) var rejectedLines = 0

    mutating func append(_ data: Data) -> [AgentEvent] {
        var result: [AgentEvent] = []
        for byte in data {
            if byte == 0x0A {
                if !discardingLine, let event = decodeLine() { result.append(event) }
                line.removeAll(keepingCapacity: true)
                discardingLine = false
            } else if !discardingLine {
                if line.count < Self.maximumLineBytes {
                    line.append(byte)
                } else {
                    rejectedLines += 1
                    line.removeAll(keepingCapacity: true)
                    discardingLine = true
                }
            }
        }
        return result
    }

    mutating func finish() -> [AgentEvent] {
        defer {
            line.removeAll(keepingCapacity: true)
            discardingLine = false
        }
        guard !discardingLine, let event = decodeLine() else { return [] }
        return [event]
    }

    private mutating func decodeLine() -> AgentEvent? {
        if line.last == 0x0D { line.removeLast() }
        guard !line.isEmpty else { return nil }
        do {
            return try JSONDecoder().decode(AgentEvent.self, from: line)
        } catch {
            rejectedLines += 1
            return nil
        }
    }
}
