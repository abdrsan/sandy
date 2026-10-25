import Foundation

/// Следит за rollout-журналами Codex (`$CODEX_HOME/sessions/**/rollout-*.jsonl`).
///
/// Их пишет ядро Codex для любой локальной нити — CLI, `codex exec`, IDE и
/// Desktop (через свой app-server). Поддерживаемого интерфейса «подписаться на
/// чужие нити» у Codex нет: app-server сообщает только о нитях, которые он сам
/// и ведёт, а Desktop держит свой app-server на stdio. Поэтому журналы.
public final class CodexMonitor {
    public struct Options: Sendable {
        /// Файлы, менявшиеся в этом окне до запуска, попадают в начальный снимок.
        public var replayWindow: TimeInterval = 12 * 3600
        /// Сколько байт с конца файла читается для начального снимка.
        public var tailBytes: UInt64 = 512 << 10
        public var maxLineBytes = 1 << 20
        public var maxReadBytes = 4 << 20
        /// Ограничение на чтение одного файла за один опрос.
        public var maxReadsPerPoll = 4
        /// Каждый какой опрос обходит всё дерево `sessions`.
        public var fullScanEvery = 10

        public init() {}
    }

    final class Tracked {
        let reader: JSONLTailReader
        var state: CodexSessionState
        var size: UInt64 = 0
        var modified = Date.distantPast
        var headLoaded = false

        init(path: String, sessionID: String, options: Options) {
            reader = JSONLTailReader(path: path, maxLineBytes: options.maxLineBytes,
                                     maxReadBytes: options.maxReadBytes)
            state = CodexSessionState(sessionID: sessionID)
        }
    }

    public let sessionsRoot: URL
    private let options: Options
    private let now: () -> Date
    private let log: (String) -> Void
    private var files: [String: Tracked] = [:]
    private var started = false
    private var polls = 0
    private var rootWasMissing = false

    public init(
        codexHome: URL,
        options: Options = Options(),
        now: @escaping () -> Date = Date.init,
        log: @escaping (String) -> Void = { _ in }
    ) {
        sessionsRoot = codexHome.appendingPathComponent("sessions", isDirectory: true)
        self.options = options
        self.now = now
        self.log = log
    }

    public static func defaultHome(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let home = environment["CODEX_HOME"], home.hasPrefix("/") {
            return URL(fileURLWithPath: home, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    }

    /// Первый вызов строит начальный снимок через `pipeline.replay`, следующие
    /// выдают живые события.
    public func poll(into pipeline: EventPipeline) {
        let initial = !started
        started = true
        let clock = now()
        polls += 1
        // Полный обход дерева — раз в `fullScanEvery` опросов. Между ними
        // смотрим только каталоги за сегодня и вчера и недавно менявшиеся
        // файлы: в дереве за месяцы работы тысячи файлов.
        let full = initial || polls % options.fullScanEvery == 0
        guard let (listing, checked) = full ? scan().map({ ($0, Set(files.keys)) }) : recentScan(now: clock)
        else {
            if !rootWasMissing { log("codex: нет каталога \(sessionsRoot.path)") }
            rootWasMissing = true
            for path in files.keys { vanish(path, pipeline: pipeline) }
            return
        }
        rootWasMissing = false

        for path in checked where listing[path] == nil {
            vanish(path, pipeline: pipeline)
        }

        for (path, meta) in listing.sorted(by: { $0.value.modified < $1.value.modified }) {
            if let tracked = files[path] {
                if meta.size != tracked.size || meta.modified != tracked.modified
                    || tracked.reader.offset < meta.size {
                    read(tracked, replay: false, pipeline: pipeline)
                }
                continue
            }
            let name = (path as NSString).lastPathComponent
            guard let sessionID = CodexRolloutAdapter.sessionID(fromFileName: name) else { continue }
            let tracked = Tracked(path: path, sessionID: sessionID, options: options)
            files[path] = tracked
            if !initial {
                // Новый файл, появившийся при работе: читаем целиком.
                read(tracked, replay: false, pipeline: pipeline)
            } else if clock.timeIntervalSince(meta.modified) <= options.replayWindow {
                if meta.size > options.tailBytes {
                    loadHead(tracked, replay: true, pipeline: pipeline)
                    tracked.reader.seek(to: meta.size - options.tailBytes, alignToLine: true)
                }
                read(tracked, replay: true, pipeline: pipeline)
            } else {
                // Старый файл: историю не поднимаем, но следим за дописыванием
                // (Desktop продолжает нить в её исходном файле).
                tracked.reader.seek(to: meta.size, alignToLine: false)
                tracked.size = meta.size
                tracked.modified = meta.modified
            }
        }
    }

    private func read(_ tracked: Tracked, replay: Bool, pipeline: EventPipeline) {
        if !tracked.headLoaded {
            if tracked.reader.offset > 0 {
                loadHead(tracked, replay: replay, pipeline: pipeline)
            } else {
                tracked.headLoaded = true
            }
        }
        var reads = 0
        while replay || reads < options.maxReadsPerPoll {
            reads += 1
            let batch: JSONLTailReader.Batch
            do {
                batch = try tracked.reader.read()
            } catch {
                if error != .missing { log("codex: не читается \(tracked.reader.path): \(error)") }
                return
            }
            if batch.didReset {
                log("codex: файл перезаписан, читаю заново: \(tracked.reader.path)")
                let id = tracked.state.sessionID
                tracked.state = CodexSessionState(sessionID: id)
                tracked.headLoaded = true
            }
            tracked.size = tracked.reader.fileSize
            for item in batch.items {
                deliver(item, tracked: tracked, replay: replay, pipeline: pipeline)
            }
            if !batch.hasMore { break }
        }
        if let modified = try? FileManager.default.attributesOfItem(atPath: tracked.reader.path)[.modificationDate] as? Date {
            tracked.modified = modified
        }
    }

    private func loadHead(_ tracked: Tracked, replay: Bool, pipeline: EventPipeline) {
        tracked.headLoaded = true
        guard let item = JSONLTailReader.firstLine(path: tracked.reader.path, limit: options.maxLineBytes)
        else { return }
        deliver(item, tracked: tracked, replay: replay, pipeline: pipeline)
    }

    private func deliver(_ item: JSONLTailReader.Item, tracked: Tracked, replay: Bool, pipeline: EventPipeline) {
        let key = "o\(item.offset)"
        let events: [AgentEvent]
        switch item {
        case .line(let data, _):
            guard let object = JSONSupport.object(from: data) else { return }
            events = CodexRolloutAdapter.events(line: object, state: &tracked.state, fallbackKey: key, now: now())
        case .oversized(let prefix, _, _):
            events = CodexRolloutAdapter.events(oversizedPrefix: prefix, state: &tracked.state,
                                                fallbackKey: key, now: now())
        }
        for event in events {
            replay ? pipeline.replay(event) : pipeline.emit(event)
        }
    }

    /// Файл пропал (архивирован, удалён, каталог недоступен). Что стало с
    /// нитью, по файлу не понять, поэтому `disconnected`, а не `session_ended`.
    private func vanish(_ path: String, pipeline: EventPipeline) {
        guard let tracked = files.removeValue(forKey: path) else { return }
        let state = tracked.state
        guard !state.isAuxiliary, state.sawMeta || state.lastKind != nil,
              pipeline.hasSession(.codex, state.sessionID) else { return }
        if let kind = pipeline.lastStateKind(.codex, state.sessionID),
           kind == .sessionEnded || kind == .disconnected { return }
        pipeline.emit(AgentEvent(
            eventID: "codex:\(state.sessionID):disconnected:\(tracked.size)",
            source: .codex, sessionID: state.sessionID, timestamp: now(),
            kind: .disconnected, projectPath: state.projectPath))
    }

    /// Каталоги за сегодня и вчера плюс файлы, менявшиеся в последний час.
    /// Возвращает и множество путей, отсутствие которых что-то значит.
    private func recentScan(now: Date) -> ([String: (size: UInt64, modified: Date)], Set<String>)? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sessionsRoot.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        var result: [String: (size: UInt64, modified: Date)] = [:]
        var checked = Set<String>()
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        for day in [now, now.addingTimeInterval(-24 * 3600)] {
            let parts = Calendar.current.dateComponents([.year, .month, .day], from: day)
            guard let y = parts.year, let m = parts.month, let d = parts.day else { continue }
            let folder = sessionsRoot.appendingPathComponent(String(format: "%04d/%02d/%02d", y, m, d), isDirectory: true)
            for url in (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? [] {
                let name = url.lastPathComponent
                guard name.hasPrefix("rollout-"), name.hasSuffix(".jsonl"),
                      let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true
                else { continue }
                result[url.path] = (UInt64(values.fileSize ?? 0), values.contentModificationDate ?? .distantPast)
            }
        }
        for (path, tracked) in files where now.timeIntervalSince(tracked.modified) < 3600 && result[path] == nil {
            checked.insert(path)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { continue }
            result[path] = ((attributes[.size] as? UInt64) ?? 0, (attributes[.modificationDate] as? Date) ?? .distantPast)
        }
        checked.formUnion(result.keys)
        return (result, checked.filter { files[$0] != nil })
    }

    private func scan() -> [String: (size: UInt64, modified: Date)]? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sessionsRoot.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsRoot, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return nil }
        var result: [String: (size: UInt64, modified: Date)] = [:]
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            guard name.hasPrefix("rollout-"), name.hasSuffix(".jsonl"),
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            result[url.path] = (UInt64(values.fileSize ?? 0), values.contentModificationDate ?? .distantPast)
        }
        return result
    }
}
