import Foundation

/// Читает почтовый ящик хуков Claude Code, считает usage по журналам сессий
/// и замечает пропавшие процессы Claude.
public final class ClaudeMonitor {
    public struct Options: Sendable {
        public var replayWindow: TimeInterval = 12 * 3600
        /// Файлы ящика старше этого удаляются при запуске монитора.
        public var retention: TimeInterval = 7 * 24 * 3600
        /// Как часто перечитывать журнал активной сессии без новых хуков.
        public var usageInterval: TimeInterval = 5
        public init() {}
    }

    final class Session {
        let reader: JSONLTailReader
        var sessionID: String?
        var owner: ProcessIdentity?
        var transcript: ClaudeTranscriptUsage?
        var lastUsageCheck = Date.distantPast
        var ended = false
        var lostOwner: ProcessIdentity?

        init(path: String) {
            reader = JSONLTailReader(path: path, maxLineBytes: 64 << 10, maxReadBytes: 1 << 20)
        }
    }

    public let spool: ClaudeSpool
    private let options: Options
    private let now: () -> Date
    private let isAlive: (ProcessIdentity) -> Bool
    private let log: (String) -> Void
    private var files: [String: Session] = [:]
    private var started = false

    public init(
        spool: ClaudeSpool,
        options: Options = Options(),
        now: @escaping () -> Date = Date.init,
        isAlive: @escaping (ProcessIdentity) -> Bool = ProcessInspector.isAlive,
        log: @escaping (String) -> Void = { _ in }
    ) {
        self.spool = spool
        self.options = options
        self.now = now
        self.isAlive = isAlive
        self.log = log
    }

    public func poll(into pipeline: EventPipeline) {
        let initial = !started
        started = true
        let clock = now()
        if initial { removeExpired(scan(), now: clock) }
        let listing = scan()

        for (path, modified) in listing.sorted(by: { $0.value < $1.value }) {
            let session: Session
            if let existing = files[path] {
                session = existing
            } else {
                session = Session(path: path)
                files[path] = session
                if initial, clock.timeIntervalSince(modified) > options.replayWindow {
                    // Старая сессия: только следим за продолжением.
                    if let size = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? UInt64 {
                        session.reader.seek(to: size, alignToLine: false)
                    }
                    continue
                }
            }
            let fresh = readRecords(session, replay: initial, pipeline: pipeline)
            updateUsage(session, force: fresh || initial, replay: initial, pipeline: pipeline)
            checkOwner(session, replay: initial, pipeline: pipeline)
        }
        for path in files.keys where listing[path] == nil { files.removeValue(forKey: path) }
    }

    /// true, если пришли новые записи.
    private func readRecords(_ session: Session, replay: Bool, pipeline: EventPipeline) -> Bool {
        var fresh = false
        for _ in 0..<8 {
            guard let batch = try? session.reader.read() else { break }
            for item in batch.items {
                guard case .line(let data, _) = item,
                      let record = ClaudeHookRecord.decode(data),
                      Identifier.sanitized(record.sessionID) != nil else { continue }
                fresh = true
                apply(record, to: session, replay: replay, pipeline: pipeline)
            }
            if !batch.hasMore { break }
        }
        return fresh
    }

    private func apply(_ record: ClaudeHookRecord, to session: Session, replay: Bool, pipeline: EventPipeline) {
        session.sessionID = record.sessionID
        if let owner = record.owner, owner != session.owner {
            session.owner = owner
            session.lostOwner = nil
        }
        if let path = record.transcriptPath, session.transcript?.path != path {
            session.transcript = ClaudeTranscriptUsage(path: path)
        }
        let events = ClaudeHookAdapter.events(
            for: record, lastKind: pipeline.lastStateKind(.claude, record.sessionID))
        for event in events {
            if event.kind == .sessionEnded { session.ended = true }
            if event.kind == .sessionStarted { session.ended = false }
            replay ? pipeline.replay(event) : pipeline.emit(event)
        }
    }

    private func updateUsage(_ session: Session, force: Bool, replay: Bool, pipeline: EventPipeline) {
        guard let sessionID = session.sessionID, let transcript = session.transcript else { return }
        let clock = now()
        guard force || transcript.hasMore
                || (!session.ended && clock.timeIntervalSince(session.lastUsageCheck) >= options.usageInterval)
        else { return }
        session.lastUsageCheck = clock
        // При запуске журнал дочитывается целиком, дальше — порциями.
        var changed = transcript.update(maxReads: replay ? 64 : 4)
        while replay, transcript.hasMore { changed = transcript.update(maxReads: 64) || changed }
        guard changed, let usage = transcript.total else { return }
        let event = AgentEvent(
            eventID: "claude:\(sessionID):usage:\(usage.inputTokens ?? 0):\(usage.outputTokens ?? 0)",
            source: .claude, sessionID: sessionID, timestamp: transcript.lastTimestamp ?? clock,
            kind: .usage, usage: usage)
        replay ? pipeline.replay(event) : pipeline.emit(event)
    }

    /// Процесс Claude пропал без SessionEnd — сессию больше не видно.
    private func checkOwner(_ session: Session, replay: Bool, pipeline: EventPipeline) {
        guard let sessionID = session.sessionID, let owner = session.owner,
              !session.ended, session.lostOwner != owner, !isAlive(owner) else { return }
        session.lostOwner = owner
        let event = AgentEvent(
            eventID: "claude:\(sessionID):disconnected:\(owner.pid):\(Int64(owner.startTime * 1000))",
            source: .claude, sessionID: sessionID, timestamp: now(), kind: .disconnected)
        replay ? pipeline.replay(event) : pipeline.emit(event)
    }

    private func scan() -> [String: Date] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: spool.directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [:] }
        var result: [String: Date] = [:]
        for url in urls where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true
            else { continue }
            result[url.path] = values.contentModificationDate ?? .distantPast
        }
        return result
    }

    private func removeExpired(_ listing: [String: Date], now: Date) {
        for (path, modified) in listing where now.timeIntervalSince(modified) > options.retention {
            try? FileManager.default.removeItem(atPath: path)
            log("claude: удалён устаревший файл ящика")
        }
    }
}
