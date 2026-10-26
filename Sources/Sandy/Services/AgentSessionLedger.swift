import Foundation

enum AgentSessionState: String, CaseIterable, Codable, Sendable {
    case idle, working, waiting, ready, ended, failed, disconnected
}

struct AgentSession: Codable, Identifiable, Equatable, Sendable {
    var id: String { "\(source.rawValue):\(sessionID)" }
    var source: AgentSource
    var sessionID: String
    var projectPath: String?
    var operation: String?
    var state: AgentSessionState
    var lastEventAt: Date
    var startedAt: Date
    var activeSeconds: TimeInterval
    var operations: Int
    var inputTokens: Int?
    var outputTokens: Int?

    // This observed interval is deliberately excluded from the saved history.
    var activeSince: Date?

    private enum CodingKeys: String, CodingKey {
        case source, sessionID, projectPath, operation, state, lastEventAt, startedAt
        case activeSeconds, operations, inputTokens, outputTokens
    }

    func activeDuration(at date: Date) -> TimeInterval {
        activeSeconds + (activeSince.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }
}

struct AgentAlert: Sendable {
    enum Kind: Sendable { case ready, waiting, failed }
    var sessionID: String
    var source: AgentSource
    var kind: Kind
}

struct AgentSummary: Identifiable, Sendable {
    var id: String
    var source: AgentSource
    var projectPath: String?
    var sessionCount: Int
    var activeSeconds: TimeInterval
    var operations: Int
    var inputTokens: Int?
    var outputTokens: Int?
}

/// Session metadata and bounded deduplication state, with no raw event payloads.
struct AgentSessionLedger: Codable, Sendable {
    private static let maximumRememberedEvents = 5_000
    private static let maximumRetainedSessions = 2_000
    private static let maximumLiveEventLag: TimeInterval = 120
    private(set) var sessions: [String: AgentSession] = [:]
    private var eventIDs: [String] = []
    private var stateTimestamps: [String: Date] = [:]
    private var knownEventIDs: Set<String> = []
    private var needsFreshEvent: Set<String> = []

    init() {}

    private enum CodingKeys: String, CodingKey { case sessions, eventIDs, stateTimestamps }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sessions = try values.decode([String: AgentSession].self, forKey: .sessions)
        eventIDs = Array(try values.decodeIfPresent([String].self, forKey: .eventIDs)?.suffix(Self.maximumRememberedEvents) ?? [])
        stateTimestamps = try values.decodeIfPresent([String: Date].self, forKey: .stateTimestamps) ?? [:]
        knownEventIDs = Set(eventIDs)
        needsFreshEvent = Set(sessions.keys)
        // Decoding alone is safe, even if the caller has not invoked restore yet.
        for id in sessions.keys where sessions[id]?.state == .working {
            sessions[id]?.state = .disconnected
        }
        limitSessionCount()
    }

    mutating func ingest(_ event: AgentEvent, receivedAt: Date) -> AgentAlert? {
        let id = "\(event.source.rawValue):\(event.sessionID)"
        let dedupID = "\(id)\u{0}\(event.eventID)"
        guard knownEventIDs.insert(dedupID).inserted else { return nil }
        eventIDs.append(dedupID)
        if eventIDs.count > Self.maximumRememberedEvents {
            let extra = eventIDs.count - Self.maximumRememberedEvents
            for expired in eventIDs.prefix(extra) { knownEventIDs.remove(expired) }
            eventIDs.removeFirst(extra)
        }

        var session = sessions[id] ?? AgentSession(
            source: event.source, sessionID: event.sessionID, projectPath: nil, operation: nil,
            state: .idle, lastEventAt: event.timestamp, startedAt: event.timestamp,
            activeSeconds: 0, operations: 0, inputTokens: nil, outputTokens: nil, activeSince: nil
        )
        session.startedAt = min(session.startedAt, event.timestamp)
        session.lastEventAt = max(session.lastEventAt, event.timestamp)
        if let input = event.usage?.inputTokens { session.inputTokens = max(session.inputTokens ?? 0, input) }
        if let output = event.usage?.outputTokens { session.outputTokens = max(session.outputTokens ?? 0, output) }

        // Usage snapshots may be delivered out of order without moving state.
        guard event.kind != .usage else {
            if session.projectPath == nil { session.projectPath = event.projectPath }
            sessions[id] = session
            limitSessionCount()
            return nil
        }
        let previousTime = stateTimestamps[id]
        let replay = previousTime.map {
            event.timestamp < $0 || (needsFreshEvent.contains(id) && event.timestamp <= $0)
        } ?? false
        // An ended session is final. A new turn uses working after ready instead.
        let resurrectsEnded = session.state == .ended && event.kind != .sessionEnded
        let resurrectsSameInstant = previousTime == event.timestamp
            && [.ready, .failed, .ended].contains(session.state)
            && [.working, .sessionStarted].contains(event.kind)
        guard !replay, !resurrectsEnded, !resurrectsSameInstant else {
            sessions[id] = session
            return nil
        }

        let lag = receivedAt.timeIntervalSince(event.timestamp)
        let isLive = lag >= -5 && lag <= Self.maximumLiveEventLag
        let previousState = session.state
        if let anchor = session.activeSince {
            // A delayed terminal event can only end the interval we observed.
            let end = event.kind == .working ? receivedAt : min(receivedAt, event.timestamp)
            session.activeSeconds += max(0, end.timeIntervalSince(anchor))
            session.activeSince = nil
        }
        stateTimestamps[id] = event.timestamp
        needsFreshEvent.remove(id)
        if let path = event.projectPath { session.projectPath = path }
        if let operation = event.operation { session.operation = operation }

        switch event.kind {
        case .sessionStarted:
            // Repeated start envelopes must not erase an already observed turn.
            session.state = previousState == .working ? .working : .idle
        case .working:
            session.state = isLive ? .working : .disconnected
            if session.operations < Int.max { session.operations += 1 }
        case .waiting: session.state = .waiting
        case .turnCompleted: session.state = .ready
        case .sessionEnded: session.state = .ended
        case .failed: session.state = .failed
        case .disconnected: session.state = .disconnected
        case .usage: break
        }
        if session.state == .working, isLive { session.activeSince = receivedAt }
        sessions[id] = session
        limitSessionCount()

        guard isLive, session.state != previousState else { return nil }
        let alertKind: AgentAlert.Kind
        switch session.state {
        case .ready: alertKind = .ready
        case .waiting: alertKind = .waiting
        case .failed: alertKind = .failed
        default: return nil
        }
        return AgentAlert(sessionID: id, source: event.source, kind: alertKind)
    }

    mutating func disconnect(sources: Set<AgentSource>, at date: Date) {
        for id in sessions.keys {
            guard var session = sessions[id], sources.contains(session.source) else { continue }
            accumulate(&session, at: date)
            session.activeSince = nil
            if [.idle, .working, .waiting].contains(session.state) { session.state = .disconnected }
            sessions[id] = session
            needsFreshEvent.insert(id)
        }
    }

    mutating func checkpoint(at date: Date) {
        for id in sessions.keys {
            guard var session = sessions[id] else { continue }
            accumulate(&session, at: date)
            sessions[id] = session
        }
    }

    mutating func restore(at date: Date) {
        // Never accumulate a saved working interval across launch or wake.
        for id in sessions.keys {
            sessions[id]?.activeSince = nil
            if let state = sessions[id]?.state, [.idle, .working, .waiting].contains(state) {
                sessions[id]?.state = .disconnected
            }
        }
        needsFreshEvent = Set(sessions.keys)
    }

    mutating func prune(before date: Date) {
        let removed = Set(sessions.values.filter { $0.lastEventAt < date }.map(\.id))
        removeSessions(removed)
    }

    private mutating func limitSessionCount() {
        guard sessions.count > Self.maximumRetainedSessions else { return }
        let oldest = sessions.values.sorted { lhs, rhs in
            let lhsActive = lhs.state == .working || lhs.state == .waiting
            let rhsActive = rhs.state == .working || rhs.state == .waiting
            if lhsActive != rhsActive { return !lhsActive }
            if lhs.lastEventAt != rhs.lastEventAt { return lhs.lastEventAt < rhs.lastEventAt }
            return lhs.id < rhs.id
        }
        removeSessions(Set(oldest.prefix(sessions.count - Self.maximumRetainedSessions).map(\.id)))
    }

    private mutating func removeSessions(_ removed: Set<String>) {
        guard !removed.isEmpty else { return }
        for id in removed {
            sessions.removeValue(forKey: id)
            stateTimestamps.removeValue(forKey: id)
            needsFreshEvent.remove(id)
        }
        eventIDs.removeAll { removed.contains(String($0.prefix(while: { $0 != "\u{0}" }))) }
        knownEventIDs = Set(eventIDs)
    }

    func summaries(at date: Date) -> [AgentSummary] {
        let groups = Dictionary(grouping: sessions.values) { "\($0.source.rawValue)\u{0}\($0.projectPath ?? "")" }
        return groups.compactMap { key, values in
            guard let first = values.first else { return nil }
            // A partial total would look complete, so preserve unknown coverage.
            let input = values.allSatisfy { $0.inputTokens != nil } ? boundedSum(values.compactMap(\.inputTokens)) : nil
            let output = values.allSatisfy { $0.outputTokens != nil } ? boundedSum(values.compactMap(\.outputTokens)) : nil
            return AgentSummary(id: key, source: first.source, projectPath: first.projectPath,
                                sessionCount: values.count,
                                activeSeconds: values.reduce(0) { $0 + $1.activeDuration(at: date) },
                                operations: boundedSum(values.map(\.operations)),
                                inputTokens: input, outputTokens: output)
        }.sorted { $0.id < $1.id }
    }

    private func accumulate(_ session: inout AgentSession, at date: Date) {
        guard let anchor = session.activeSince, date >= anchor else { return }
        session.activeSeconds += date.timeIntervalSince(anchor)
        session.activeSince = date
    }

    private func boundedSum(_ values: [Int]) -> Int {
        values.reduce(0) { value, addition in
            let (sum, overflow) = value.addingReportingOverflow(addition)
            return overflow ? Int.max : sum
        }
    }
}
