import Foundation

/// Накопленные токены сессии Claude Code по её журналу (`transcript_path`).
///
/// Хуки токенов не сообщают. Журнал — внутренний формат Claude Code, не
/// документированный как API, поэтому разбор минимальный: из строк
/// `"type":"assistant"` берутся только `message.id` и числа из
/// `message.usage`. Текст сообщений не читается в структуры и не хранится.
/// Одно сообщение пишется несколькими строками с одним id — учитывается
/// последнее значение.
public final class ClaudeTranscriptUsage {
    struct Counts: Equatable {
        var input = 0
        var output = 0
        var cached = 0
    }

    private let reader: JSONLTailReader
    private var perMessage: [String: Counts] = [:]
    private let maxMessages = 200_000
    public private(set) var lastTimestamp: Date?

    public init(path: String) {
        reader = JSONLTailReader(path: path, maxLineBytes: 1 << 20, maxReadBytes: 4 << 20)
    }

    public var path: String { reader.path }

    /// Итог или nil, если ни одного ответа модели ещё нет.
    public var total: AgentUsage? {
        guard !perMessage.isEmpty else { return nil }
        let sum = perMessage.values.reduce(into: Counts()) {
            $0.input += $1.input; $0.output += $1.output; $0.cached += $1.cached
        }
        return AgentUsage(inputTokens: sum.input, outputTokens: sum.output, cachedInputTokens: sum.cached)
    }

    /// Дочитать новое. Не больше `maxReads` порций за вызов.
    @discardableResult
    public func update(maxReads: Int = 4) -> Bool {
        let before = total
        for _ in 0..<maxReads {
            guard let batch = try? reader.read() else { break }
            if batch.didReset { perMessage.removeAll() }
            for item in batch.items { ingest(item) }
            if !batch.hasMore { break }
        }
        return total != before
    }

    public var hasMore: Bool { reader.offset < reader.fileSize }

    private func ingest(_ item: JSONLTailReader.Item) {
        switch item {
        case .line(let data, let offset):
            // Дешёвый отсев до JSON-разбора: большинство строк — не ответы модели.
            guard data.range(of: Data("\"assistant\"".utf8)) != nil,
                  let object = JSONSupport.object(from: data),
                  object.string("type") == "assistant",
                  let message = object.object("message"),
                  let usage = message.object("usage") else { return }
            let key = message.string("id") ?? object.string("requestId") ?? "line@\(offset)"
            record(key, counts(usage.int), timestamp: object.string("timestamp"))
        case .oversized(let prefix, let suffix, let offset):
            // Огромная строка (большой tool_use). id стоит в начале, usage и
            // тип записи — в конце.
            let tail = String(decoding: suffix, as: UTF8.self)
            guard tail.contains("\"type\":\"assistant\"") || tail.contains("\"type\": \"assistant\""),
                  tail.contains("\"usage\"") else { return }
            let head = String(decoding: prefix, as: UTF8.self)
            let key = JSONSupport.sniffStrings("id", in: head).first(where: { $0.hasPrefix("msg_") })
                ?? "line@\(offset)"
            let usageText = tail.components(separatedBy: "\"usage\"").last ?? ""
            record(key, counts { JSONSupport.sniffLastInt($0, in: usageText) },
                   timestamp: JSONSupport.sniffString("timestamp", in: tail))
        }
    }

    private func counts(_ value: (String) -> Int?) -> Counts {
        let cacheRead = value("cache_read_input_tokens") ?? 0
        let cacheWrite = value("cache_creation_input_tokens") ?? 0
        return Counts(
            input: (value("input_tokens") ?? 0) + cacheRead + cacheWrite,
            output: value("output_tokens") ?? 0,
            cached: cacheRead)
    }

    private func record(_ key: String, _ counts: Counts, timestamp: String?) {
        guard perMessage[key] != nil || perMessage.count < maxMessages else { return }
        perMessage[key] = counts
        if let date = timestamp.flatMap(AgentTimestamp.parse) { lastTimestamp = date }
    }
}
