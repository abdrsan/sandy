import Foundation
import Testing
@testable import AgentBridgeCore

struct ClaudeBridgeTests {
    private func record(_ hook: String, session: String = "s1", extra: [String: Any] = [:],
                        at seconds: TimeInterval = 0, owner: ProcessIdentity? = nil) throws -> ClaudeHookRecord {
        try #require(ClaudeHookRecord.make(
            payload: Fixture.claudePayload(hook, session: session, extra: extra),
            now: Date(timeIntervalSince1970: 1_790_000_000 + seconds), owner: owner))
    }

    @Test func hookRecordKeepsOnlyAllowlistedFields() throws {
        let rec = try record("PreToolUse", extra: ["tool_name": "Bash", "tool_use_id": "toolu_1"])
        let line = String(decoding: rec.jsonLine(), as: UTF8.self)
        #expect(!line.contains(Fixture.secret))
        #expect(!line.contains("Bearer"))
        #expect(!line.contains("tool_input"))
        #expect(rec.toolName == "Bash")
        #expect(rec.cwd == "/Users/tester/project-s1")
        #expect(ClaudeHookRecord.decode(rec.jsonLine()) == rec)
    }

    @Test func malformedPayloadsAreIgnored() {
        let now = Date()
        for payload in ["", "{", "[]", "null", "{\"session_id\":\"../../etc\",\"hook_event_name\":\"Stop\"}",
                        "{\"session_id\":\"a b\",\"hook_event_name\":\"Stop\"}",
                        "{\"hook_event_name\":\"Stop\"}"] {
            #expect(ClaudeHookRecord.make(payload: Data(payload.utf8), now: now, owner: nil) == nil)
        }
    }

    @Test func oversizedPayloadStillYieldsAnEvent() throws {
        let big = String(repeating: "y", count: 40 << 20)
        var data = Data("{\"session_id\":\"s9\",\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",".utf8)
        data.append(Data("\"tool_input\":{\"content\":\"\(big)".utf8))   // обрезан, не JSON
        let rec = try #require(ClaudeHookRecord.make(payload: data, now: Date(), owner: nil))
        #expect(rec.sessionID == "s9")
        #expect(rec.toolName == "Write")
    }

    @Test func hookEventsMapToStates() throws {
        func kinds(_ hook: String, _ extra: [String: Any] = [:], last: AgentEventKind? = nil) throws -> [AgentEventKind] {
            ClaudeHookAdapter.events(for: try record(hook, extra: extra), lastKind: last).map(\.kind)
        }
        #expect(try kinds("SessionStart", ["source": "startup"]) == [.sessionStarted])
        #expect(try kinds("SessionStart", ["source": "compact"]) == [])
        #expect(try kinds("UserPromptSubmit") == [.working])
        #expect(try kinds("PermissionRequest", ["tool_name": "Bash"]) == [.waiting])
        #expect(try kinds("Notification", ["notification_type": "permission_prompt"]) == [.waiting])
        #expect(try kinds("Notification", ["notification_type": "idle_prompt"], last: .turnCompleted) == [])
        #expect(try kinds("Notification", ["notification_type": "idle_prompt"], last: .working) == [.waiting])
        #expect(try kinds("Stop") == [.turnCompleted])
        #expect(try kinds("SessionEnd", ["reason": "other"]) == [.sessionEnded])

        let failure = ClaudeHookAdapter.events(
            for: try record("StopFailure", extra: ["error": "rate_limit", "error_details": Fixture.secret]),
            lastKind: .working)
        #expect(failure.map(\.kind) == [.failed])
        #expect(failure.first?.error == "rate_limit")
        let odd = ClaudeHookAdapter.events(for: try record("StopFailure", extra: ["error": Fixture.secret]),
                                           lastKind: nil)
        #expect(odd.first?.error == "unknown")
    }

    @Test func spoolMonitorTracksParallelSessionsAndDedupes() throws {
        let dir = try Fixture.temporaryDirectory()
        let spool = ClaudeSpool(directory: dir)
        let out = Collected()
        let monitor = ClaudeMonitor(spool: spool, isAlive: { _ in true })
        monitor.poll(into: out.pipeline)
        out.pipeline.flushReplay()

        let start1 = try record("SessionStart", session: "s1", extra: ["source": "startup"])
        try spool.append(start1)
        try spool.append(try record("SessionStart", session: "s2", extra: ["source": "startup"], at: 1))
        try spool.append(try record("PreToolUse", session: "s1", extra: ["tool_name": "Edit"], at: 2))
        try spool.append(try record("PostToolUse", session: "s1", extra: ["tool_name": "Edit"], at: 3))
        try spool.append(try record("PostToolUse", session: "s1", extra: ["tool_name": "Edit"], at: 4))
        try spool.append(start1)   // повторная доставка
        try spool.append(try record("Stop", session: "s2", at: 5))
        monitor.poll(into: out.pipeline)

        // Два PostToolUse подряд дают одно «работает».
        #expect(out.kinds("s1") == [.sessionStarted, .working, .working])
        #expect(out.kinds("s2") == [.sessionStarted, .turnCompleted])
        #expect(out.events.first { $0.sessionID == "s1" && $0.tool == "Edit" }?.operation == OperationLabels.editFile)
        #expect(!out.lines.contains(Fixture.secret))
    }

    @Test func restartRestoresLiveSessionsOnlyAndKeepsIDs() throws {
        let dir = try Fixture.temporaryDirectory()
        let spool = ClaudeSpool(directory: dir)
        try spool.append(try record("SessionStart", session: "live", extra: ["source": "startup"]))
        try spool.append(try record("PermissionRequest", session: "live", extra: ["tool_name": "Bash"], at: 1))
        try spool.append(try record("SessionStart", session: "done", extra: ["source": "startup"]))
        try spool.append(try record("SessionEnd", session: "done", at: 2))

        let first = Collected()
        ClaudeMonitor(spool: spool, isAlive: { _ in true }).poll(into: first.pipeline)
        first.pipeline.flushReplay()
        let second = Collected()
        ClaudeMonitor(spool: spool, isAlive: { _ in true }).poll(into: second.pipeline)
        second.pipeline.flushReplay()

        #expect(first.kinds("live") == [.sessionStarted, .waiting])
        #expect(first.kinds("done") == [])
        #expect(first.events.map(\.eventID) == second.events.map(\.eventID))
    }

    @Test func vanishedClaudeProcessDisconnectsSession() throws {
        let dir = try Fixture.temporaryDirectory()
        let spool = ClaudeSpool(directory: dir)
        let owner = ProcessIdentity(pid: 4242, startTime: 100)
        var alive = true
        let out = Collected()
        let monitor = ClaudeMonitor(spool: spool, isAlive: { _ in alive })
        monitor.poll(into: out.pipeline)
        out.pipeline.flushReplay()
        try spool.append(try record("SessionStart", extra: ["source": "startup"], owner: owner))
        try spool.append(try record("UserPromptSubmit", at: 1, owner: owner))
        monitor.poll(into: out.pipeline)
        alive = false
        monitor.poll(into: out.pipeline)
        monitor.poll(into: out.pipeline)
        #expect(out.kinds("s1") == [.sessionStarted, .working, .disconnected])
    }

    @Test func realProcessLivenessUsesStartTime() throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        let identity = try #require(ProcessInspector.identity(of: child.processIdentifier))
        #expect(ProcessInspector.isAlive(identity))
        var reused = identity
        reused.startTime -= 10
        #expect(!ProcessInspector.isAlive(reused))
        child.terminate()
        child.waitUntilExit()
        #expect(!ProcessInspector.isAlive(identity))
    }

    @Test func transcriptUsageIsCumulativeAndDedupedByMessage() throws {
        let dir = try Fixture.temporaryDirectory()
        let transcript = dir.appendingPathComponent("t.jsonl")
        try transcript.write([
            Fixture.json(["type": "user", "message": ["role": "user", "content": Fixture.secret]]),
            Fixture.claudeAssistantLine(id: "msg_1", input: 10, output: 5, cacheRead: 100, cacheWrite: 20),
            // То же сообщение, второй блок контента: учитывается один раз.
            Fixture.claudeAssistantLine(id: "msg_1", input: 10, output: 7, cacheRead: 100, cacheWrite: 20)
        ])
        let usage = ClaudeTranscriptUsage(path: transcript.path)
        #expect(usage.update())
        #expect(usage.total == AgentUsage(inputTokens: 130, outputTokens: 7, cachedInputTokens: 100))

        let hugeText = String(repeating: "z", count: 1_300_000)
        let huge = Fixture.json([
            "message": ["id": "msg_2", "content": [["type": "text", "text": hugeText]],
                        "usage": ["input_tokens": 1, "output_tokens": 50,
                                  "cache_read_input_tokens": 0, "cache_creation_input_tokens": 0]],
            "type": "assistant"
        ])
        try transcript.write([huge], append: true)
        #expect(usage.update())
        #expect(usage.total == AgentUsage(inputTokens: 131, outputTokens: 57, cachedInputTokens: 100))
        #expect(!usage.update())
    }

    @Test func spoolRotatesInsteadOfGrowingForever() throws {
        let dir = try Fixture.temporaryDirectory()
        var spool = ClaudeSpool(directory: dir)
        spool.maxFileBytes = 2_000
        for i in 0..<50 { try spool.append(try record("PreToolUse", at: Double(i))) }
        let size = try #require(try FileManager.default.attributesOfItem(
            atPath: spool.fileURL(for: "s1").path)[.size] as? Int)
        #expect(size <= 2_000)
        let mode = try #require(try FileManager.default.attributesOfItem(
            atPath: spool.fileURL(for: "s1").path)[.posixPermissions] as? Int)
        #expect(mode == 0o600)
    }

    @Test func spoolRefusesSymlinkedSessionFile() throws {
        let dir = try Fixture.temporaryDirectory()
        let victim = dir.appendingPathComponent("victim.txt")
        try Data("keep".utf8).write(to: victim)
        let spool = ClaudeSpool(directory: dir.appendingPathComponent("spool"))
        try spool.append(try record("Stop", session: "other"))
        try FileManager.default.createSymbolicLink(at: spool.fileURL(for: "s1"), withDestinationURL: victim)
        #expect(throws: ClaudeSpool.AppendError.self) { try spool.append(try record("Stop")) }
        #expect(try String(contentsOf: victim, encoding: .utf8) == "keep")
    }
}
