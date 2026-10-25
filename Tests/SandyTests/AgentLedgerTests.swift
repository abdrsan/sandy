import Foundation
import Testing
@testable import Sandy

struct AgentLedgerTests {
    private let start = Date(timeIntervalSince1970: 1_793_000_000)

    private func event(_ id: String, _ kind: AgentEvent.Kind, at seconds: TimeInterval,
                       source: AgentSource = .codex, session: String = "a", project: String? = "/project",
                       usage: AgentUsage? = nil) -> AgentEvent {
        AgentEvent(eventID: id, source: source, sessionID: session, timestamp: start.addingTimeInterval(seconds),
                   kind: kind, projectPath: project, operation: kind == .working ? "Read file" : nil, usage: usage)
    }

    private func ingest(_ ledger: inout AgentSessionLedger, _ id: String, _ kind: AgentEvent.Kind,
                        at seconds: TimeInterval, received: TimeInterval? = nil,
                        source: AgentSource = .codex, session: String = "a", project: String? = "/project",
                        usage: AgentUsage? = nil) -> AgentAlert? {
        ledger.ingest(event(id, kind, at: seconds, source: source, session: session, project: project, usage: usage),
                      receivedAt: start.addingTimeInterval(received ?? seconds))
    }

    @Test func startIsIdleAndOnlyObservedWorkingTimeCounts() throws {
        var ledger = AgentSessionLedger()
        #expect(ingest(&ledger, "start", .sessionStarted, at: 0) == nil)
        #expect(ledger.sessions["codex:a"]?.state == .idle)
        ledger.checkpoint(at: start.addingTimeInterval(10))
        #expect(ledger.sessions["codex:a"]?.activeSeconds == 0)
        _ = ingest(&ledger, "work", .working, at: 10)
        #expect(ledger.sessions["codex:a"]?.activeDuration(at: start.addingTimeInterval(15)) == 5)
        #expect(ingest(&ledger, "wait", .waiting, at: 20)?.kind == .waiting)
        _ = ingest(&ledger, "ready", .turnCompleted, at: 80)
        let session = try #require(ledger.sessions["codex:a"])
        #expect(session.state == .ready)
        #expect(session.activeDuration(at: start.addingTimeInterval(100)) == 10)
        #expect(session.operations == 1)
        #expect(session.state != .ended)
        _ = ingest(&ledger, "next", .working, at: 100)
        #expect(ingest(&ledger, "next-ready", .turnCompleted, at: 105)?.kind == .ready)
        _ = ingest(&ledger, "ended", .sessionEnded, at: 110)
        #expect(ledger.sessions["codex:a"]?.state == .ended)
        #expect(ledger.sessions["codex:a"]?.activeSeconds == 15)
    }

    @Test func duplicateEventsAndRepeatedTerminalStatesDoNotRepeatAlertsOrOperations() {
        var ledger = AgentSessionLedger()
        _ = ingest(&ledger, "work", .working, at: 0)
        _ = ingest(&ledger, "work", .working, at: 0, received: 1)
        #expect(ingest(&ledger, "ready", .turnCompleted, at: 10)?.kind == .ready)
        #expect(ingest(&ledger, "ready", .turnCompleted, at: 10, received: 11) == nil)
        #expect(ingest(&ledger, "ready-copy", .turnCompleted, at: 11) == nil)
        #expect(ledger.sessions["codex:a"]?.operations == 1)
        #expect(ledger.sessions["codex:a"]?.activeSeconds == 10)
    }

    @Test func sameSessionAndEventIDsAreIsolatedBySourceAndSession() {
        var ledger = AgentSessionLedger()
        _ = ingest(&ledger, "same", .working, at: 0)
        _ = ingest(&ledger, "same", .working, at: 0, source: .claude)
        _ = ingest(&ledger, "same", .working, at: 0, session: "b")
        _ = ingest(&ledger, "stop", .failed, at: 5)
        #expect(ledger.sessions.count == 3)
        #expect(ledger.sessions["codex:a"]?.state == .failed)
        #expect(ledger.sessions["claude:a"]?.state == .working)
        #expect(ledger.sessions["codex:b"]?.state == .working)
    }

    @Test func cumulativeUsageIsMonotonicAndMissingCoverageRemainsUnknown() throws {
        var ledger = AgentSessionLedger()
        _ = ingest(&ledger, "usage1", .usage, at: 0, usage: AgentUsage(inputTokens: 100, outputTokens: 20))
        _ = ingest(&ledger, "usage2", .usage, at: 2, usage: AgentUsage(inputTokens: 150, outputTokens: 30))
        _ = ingest(&ledger, "usage-old", .usage, at: 1, usage: AgentUsage(inputTokens: 120))
        #expect(ledger.sessions["codex:a"]?.inputTokens == 150)
        #expect(ledger.sessions["codex:a"]?.outputTokens == 30)
        _ = ingest(&ledger, "b-start", .sessionStarted, at: 3, session: "b")
        var summary = try #require(ledger.summaries(at: start.addingTimeInterval(5)).first)
        #expect(summary.sessionCount == 2)
        #expect(summary.inputTokens == nil)
        #expect(summary.outputTokens == nil)
        _ = ingest(&ledger, "b-usage", .usage, at: 6, session: "b", usage: AgentUsage(inputTokens: 10))
        summary = try #require(ledger.summaries(at: start.addingTimeInterval(6)).first)
        #expect(summary.inputTokens == 160)
        #expect(summary.outputTokens == nil)
    }

    @Test func checkpointDisconnectAndRestoreExcludeSleepAndOfflineGaps() throws {
        var ledger = AgentSessionLedger()
        _ = ingest(&ledger, "work", .working, at: 0)
        ledger.checkpoint(at: start.addingTimeInterval(5))
        ledger.disconnect(sources: [.codex], at: start.addingTimeInterval(10))
        #expect(ledger.sessions["codex:a"]?.activeSeconds == 10)
        #expect(ledger.sessions["codex:a"]?.state == .disconnected)
        #expect(ledger.sessions["codex:a"]?.activeDuration(at: start.addingTimeInterval(1_000)) == 10)
        _ = ingest(&ledger, "resume", .working, at: 1_000)
        ledger.checkpoint(at: start.addingTimeInterval(1_005))
        let data = try JSONEncoder().encode(ledger)
        var restored = try JSONDecoder().decode(AgentSessionLedger.self, from: data)
        restored.restore(at: start.addingTimeInterval(10_000))
        #expect(restored.sessions["codex:a"]?.state == .disconnected)
        #expect(restored.sessions["codex:a"]?.activeDuration(at: start.addingTimeInterval(10_000)) == 15)
        #expect(ingest(&restored, "resume", .working, at: 1_000, received: 10_000) == nil)
        #expect(ingest(&restored, "unknown-replay", .working, at: 1_000, received: 10_000) == nil)
        #expect(restored.sessions["codex:a"]?.operations == 2)
        _ = ingest(&restored, "new-work", .working, at: 10_001)
        _ = ingest(&restored, "new-ready", .turnCompleted, at: 10_004)
        #expect(restored.sessions["codex:a"]?.activeSeconds == 18)
    }

    @Test func historicalAndOutOfOrderEventsCannotResurrectOrNotify() {
        var ledger = AgentSessionLedger()
        _ = ingest(&ledger, "historical-work", .working, at: 0, received: 1_000)
        #expect(ledger.sessions["codex:a"]?.state == .disconnected)
        #expect(ledger.sessions["codex:a"]?.activeSeconds == 0)
        #expect(ingest(&ledger, "historical-ready", .turnCompleted, at: 20, received: 1_000) == nil)
        #expect(ledger.sessions["codex:a"]?.state == .ready)
        #expect(ingest(&ledger, "older-work", .working, at: 10, received: 1_001) == nil)
        #expect(ledger.sessions["codex:a"]?.state == .ready)
        _ = ingest(&ledger, "ended", .sessionEnded, at: 1_002)
        #expect(ingest(&ledger, "after-ended", .working, at: 1_003) == nil)
        #expect(ledger.sessions["codex:a"]?.state == .ended)
        #expect(ledger.sessions["codex:a"]?.operations == 1)
    }

    @Test func delayedTerminalNeverCountsBeforeConnection() {
        var ledger = AgentSessionLedger()
        _ = ingest(&ledger, "backfill-work", .working, at: 0, received: 30)
        _ = ingest(&ledger, "backfill-ready", .turnCompleted, at: 20, received: 31)
        #expect(ledger.sessions["codex:a"]?.activeSeconds == 0)
        _ = ingest(&ledger, "fresh-work", .working, at: 40)
        _ = ingest(&ledger, "delayed-ready", .turnCompleted, at: 45, received: 60)
        #expect(ledger.sessions["codex:a"]?.activeSeconds == 5)
    }

    @Test func restoreKeepsReadyAndDeduplicationWithoutFalseAlert() throws {
        var ledger = AgentSessionLedger()
        _ = ingest(&ledger, "work", .working, at: 0)
        _ = ingest(&ledger, "ready", .turnCompleted, at: 3)
        var restored = try JSONDecoder().decode(AgentSessionLedger.self, from: JSONEncoder().encode(ledger))
        restored.restore(at: start.addingTimeInterval(5))
        #expect(ingest(&restored, "ready", .turnCompleted, at: 3, received: 5) == nil)
        #expect(ingest(&restored, "same-time-ready", .turnCompleted, at: 3, received: 5) == nil)
        #expect(ingest(&restored, "old-wait", .waiting, at: 2, received: 5) == nil)
        #expect(restored.sessions["codex:a"]?.state == .ready)
    }

    @Test func groupingPruningAndPartialSourceDisconnectAreIndependent() {
        var ledger = AgentSessionLedger()
        _ = ingest(&ledger, "a", .working, at: 0)
        _ = ingest(&ledger, "b", .working, at: 1, source: .claude)
        _ = ingest(&ledger, "c", .sessionStarted, at: 2, session: "c", project: "/other")
        ledger.disconnect(sources: [.codex], at: start.addingTimeInterval(3))
        #expect(ledger.sessions["claude:a"]?.state == .working)
        #expect(ledger.summaries(at: start.addingTimeInterval(4)).count == 3)
        ledger.prune(before: start.addingTimeInterval(1))
        #expect(ledger.sessions["codex:a"] == nil)
        #expect(ledger.sessions.count == 2)
    }

    @Test func retentionEvictsOldestInactiveSessionBeforeActiveWork() {
        var ledger = AgentSessionLedger()
        _ = ingest(&ledger, "active", .working, at: 0, session: "active")
        for index in 0..<2_000 {
            _ = ingest(&ledger, "inactive-\(index)", .sessionStarted, at: Double(index + 1), session: "inactive-\(index)")
        }
        #expect(ledger.sessions.count == 2_000)
        #expect(ledger.sessions["codex:active"]?.state == .working)
        #expect(ledger.sessions["codex:inactive-0"] == nil)
        #expect(ledger.sessions["codex:inactive-1999"] != nil)
    }

    @Test func operationCountSaturatesWhenSavedCounterIsAlreadyAtIntegerLimit() throws {
        var ledger = AgentSessionLedger()
        _ = ingest(&ledger, "start", .sessionStarted, at: 0)
        let original = try JSONEncoder().encode(ledger)
        var object = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
        var sessions = try #require(object["sessions"] as? [String: [String: Any]])
        sessions["codex:a"]?["operations"] = Int.max
        object["sessions"] = sessions
        var restored = try JSONDecoder().decode(AgentSessionLedger.self, from: JSONSerialization.data(withJSONObject: object))
        _ = ingest(&restored, "new-work", .working, at: 1)
        #expect(restored.sessions["codex:a"]?.operations == Int.max)
    }

    @Test func persistedDeduplicationWindowRemainsBounded() throws {
        var ledger = AgentSessionLedger()
        for index in 0..<5_010 {
            _ = ingest(&ledger, "usage-\(index)", .usage, at: Double(index), usage: AgentUsage(inputTokens: index))
        }
        let data = try JSONEncoder().encode(ledger)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let ids = try #require(object["eventIDs"] as? [String])
        #expect(ids.count == 5_000)
        var restored = try JSONDecoder().decode(AgentSessionLedger.self, from: data)
        _ = ingest(&restored, "usage-5009", .usage, at: 5_009, usage: AgentUsage(inputTokens: 999_999))
        #expect(restored.sessions["codex:a"]?.inputTokens == 5_009)
    }
}
