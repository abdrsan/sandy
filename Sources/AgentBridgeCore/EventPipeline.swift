import Foundation

/// Общая точка выхода событий обоих источников.
///
/// - Удаляет повторы по `event_id` (повторное чтение файла после усечения,
///   повторная доставка хука).
/// - Не повторяет подряд одинаковое состояние (`working` с тем же действием).
/// - Подставляет известный `project_path`, если событие его не несёт.
/// - При запуске копит историю молча (`replay`) и отдаёт по каждой живой
///   сессии только снимок: начало, последнее состояние и последний usage, с их
///   исходными идентификаторами. Поэтому переподключение не плодит дублей.
public final class EventPipeline {
    public struct SessionKey: Hashable, Sendable {
        public var source: AgentSource
        public var sessionID: String
    }

    struct Session {
        var started: AgentEvent?
        var lastState: AgentEvent?
        var lastUsage: AgentEvent?
        var projectPath: String?
        var replayed = false
        var order = 0
    }

    private let output: (AgentEvent) -> Void
    private var sessions: [SessionKey: Session] = [:]
    private var seen = Set<String>()
    private var seenOrder: [String] = []
    private var seenHead = 0
    private let seenCapacity: Int
    private var counter = 0

    public init(seenCapacity: Int = 50_000, output: @escaping (AgentEvent) -> Void) {
        self.seenCapacity = seenCapacity
        self.output = output
    }

    public func lastStateKind(_ source: AgentSource, _ sessionID: String) -> AgentEventKind? {
        sessions[SessionKey(source: source, sessionID: sessionID)]?.lastState?.kind
    }

    public func hasSession(_ source: AgentSource, _ sessionID: String) -> Bool {
        sessions[SessionKey(source: source, sessionID: sessionID)] != nil
    }

    public func projectPath(_ source: AgentSource, _ sessionID: String) -> String? {
        sessions[SessionKey(source: source, sessionID: sessionID)]?.projectPath
    }

    /// Живое событие.
    public func emit(_ event: AgentEvent) {
        if let accepted = accept(event, replay: false) { output(accepted) }
    }

    /// Событие из истории до запуска: только запоминается.
    public func replay(_ event: AgentEvent) {
        _ = accept(event, replay: true)
    }

    /// Снимок накопленного при запуске. Завершённые и потерянные сессии
    /// пропускаются: в начальном состоянии интерфейсу они не нужны.
    public func flushReplay() {
        let pending = sessions.filter { $0.value.replayed }.sorted { $0.value.order < $1.value.order }
        for (key, session) in pending {
            sessions[key]?.replayed = false
            if let kind = session.lastState?.kind, kind == .sessionEnded || kind == .disconnected { continue }
            var snapshot: [AgentEvent] = []
            if let started = session.started { snapshot.append(started) }
            if let state = session.lastState, state.eventID != session.started?.eventID {
                snapshot.append(state)
            }
            if let usage = session.lastUsage { snapshot.append(usage) }
            snapshot.forEach(output)
        }
    }

    private func accept(_ incoming: AgentEvent, replay: Bool) -> AgentEvent? {
        guard !seen.contains(incoming.eventID) else { return nil }
        remember(incoming.eventID)

        let key = SessionKey(source: incoming.source, sessionID: incoming.sessionID)
        var session = sessions[key] ?? Session()
        counter += 1
        session.order = counter
        var event = incoming
        if let path = event.projectPath {
            session.projectPath = path
        } else {
            event.projectPath = session.projectPath
        }

        var suppressed = false
        if event.kind == .usage {
            suppressed = session.lastUsage?.usage == event.usage
            if !suppressed { session.lastUsage = event }
        } else {
            if let last = session.lastState, last.kind == event.kind,
               last.operation == event.operation, last.tool == event.tool,
               last.projectPath == event.projectPath, last.error == event.error,
               event.kind == .working || event.kind == .waiting {
                suppressed = true
            } else {
                session.lastState = event
                if event.kind == .sessionStarted { session.started = event }
            }
        }
        if replay { session.replayed = true }
        sessions[key] = session
        return replay || suppressed ? nil : event
    }

    private func remember(_ id: String) {
        seen.insert(id)
        seenOrder.append(id)
        if seenOrder.count - seenHead > seenCapacity {
            seen.remove(seenOrder[seenHead])
            seenHead += 1
            if seenHead > seenCapacity {
                seenOrder.removeFirst(seenHead)
                seenHead = 0
            }
        }
    }
}
