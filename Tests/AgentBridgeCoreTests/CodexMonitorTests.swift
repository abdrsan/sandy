import Foundation
import Testing
@testable import AgentBridgeCore

struct CodexMonitorTests {
    let a = "01a1740b-5fef-7ea1-bd04-6bc71f85b051"
    let b = "01a1740a-62c4-70b3-a000-8dacd682e6dc"

    private func monitor(_ home: URL, fullScanEvery: Int = 10) -> CodexMonitor {
        var options = CodexMonitor.Options()
        options.fullScanEvery = fullScanEvery
        return CodexMonitor(codexHome: home, options: options)
    }

    @Test func parallelSessionsAreSeparatedAndAttributedToProjects() throws {
        let home = try Fixture.temporaryDirectory()
        let fileA = Fixture.codexRollout(home, id: a)
        let fileB = Fixture.codexRollout(home, id: b)
        try fileA.write([Fixture.codexMeta(id: a, cwd: "/work/alpha")])
        try fileB.write([Fixture.codexMeta(id: b, cwd: "/work/beta")])
        let out = Collected()
        let codex = monitor(home)
        codex.poll(into: out.pipeline)
        out.pipeline.flushReplay()
        #expect(out.events.map(\.kind) == [.sessionStarted, .sessionStarted])

        try fileA.write([Fixture.codexEvent("task_started", ordinal: 1),
                         Fixture.codexToolCall("exec", ordinal: 2)], append: true)
        try fileB.write([Fixture.codexEvent("task_started", ordinal: 1)], append: true)
        try fileA.write([Fixture.codexComplete(ordinal: 3)], append: true)
        codex.poll(into: out.pipeline)

        #expect(out.kinds(a) == [.sessionStarted, .working, .working, .turnCompleted])
        #expect(out.kinds(b) == [.sessionStarted, .working])
        #expect(out.events.filter { $0.sessionID == a }.allSatisfy { $0.projectPath == "/work/alpha" })
        #expect(out.events.filter { $0.sessionID == b }.allSatisfy { $0.projectPath == "/work/beta" })
        let tool = try #require(out.events.first { $0.tool == "exec" })
        #expect(tool.operation == OperationLabels.runCode)
        #expect(Set(out.events.map(\.eventID)).count == out.events.count)
    }

    @Test func turnCompletedIsNotSessionEndAndNothingSensitiveLeaks() throws {
        let home = try Fixture.temporaryDirectory()
        let file = Fixture.codexRollout(home, id: a)
        try file.write([Fixture.codexMeta(id: a, cwd: "/work/alpha"),
                        Fixture.codexEvent("task_started", ordinal: 1),
                        Fixture.codexToolCall("shell", ordinal: 2, custom: false),
                        Fixture.codexMessage(ordinal: 3),
                        Fixture.codexComplete(ordinal: 4)])
        let out = Collected()
        let codex = monitor(home)
        codex.poll(into: out.pipeline)   // первый опрос — снимок
        out.pipeline.flushReplay()
        #expect(out.kinds(a) == [.sessionStarted, .turnCompleted])
        #expect(!out.lines.contains(Fixture.secret))
        #expect(!out.lines.contains("Bearer"))
        #expect(!out.lines.contains("session_ended"))
    }

    @Test func partialLineWaitsForItsNewline() throws {
        let home = try Fixture.temporaryDirectory()
        let file = Fixture.codexRollout(home, id: a)
        try file.write([Fixture.codexMeta(id: a, cwd: "/work/alpha")])
        let out = Collected()
        let codex = monitor(home)
        codex.poll(into: out.pipeline)
        out.pipeline.flushReplay()

        let line = Fixture.codexComplete(ordinal: 1)
        let cut = line.index(line.startIndex, offsetBy: line.count / 2)
        try file.write([String(line[..<cut])], append: true, newline: false)
        codex.poll(into: out.pipeline)
        #expect(out.kinds(a) == [.sessionStarted])

        try file.write([String(line[cut...])], append: true)
        codex.poll(into: out.pipeline)
        #expect(out.kinds(a) == [.sessionStarted, .turnCompleted])
    }

    @Test func restartReplaysSnapshotWithTheSameIDs() throws {
        let home = try Fixture.temporaryDirectory()
        let file = Fixture.codexRollout(home, id: a)
        try file.write([Fixture.codexMeta(id: a, cwd: "/work/alpha")])
        let first = Collected()
        let codex = monitor(home)
        codex.poll(into: first.pipeline)
        first.pipeline.flushReplay()
        try file.write([Fixture.codexEvent("task_started", ordinal: 1),
                        Fixture.codexTokens(ordinal: 2, input: 100, output: 10, cached: 40),
                        Fixture.codexToolCall("apply_patch", ordinal: 3)], append: true)
        codex.poll(into: first.pipeline)

        // Новый процесс хелпера поверх тех же файлов.
        let second = Collected()
        let restarted = monitor(home)
        restarted.poll(into: second.pipeline)
        second.pipeline.flushReplay()
        #expect(second.kinds(a) == [.sessionStarted, .working, .usage])
        let firstIDs = Set(first.events.map(\.eventID))
        #expect(second.events.allSatisfy { firstIDs.contains($0.eventID) })
        #expect(second.events[1].operation == OperationLabels.editFile)
    }

    @Test func usageIsCumulativeAndNotRepeated() throws {
        let home = try Fixture.temporaryDirectory()
        let file = Fixture.codexRollout(home, id: a)
        try file.write([Fixture.codexMeta(id: a, cwd: "/work/alpha")])
        let out = Collected()
        let codex = monitor(home)
        codex.poll(into: out.pipeline)
        out.pipeline.flushReplay()
        try file.write([Fixture.codexTokens(ordinal: 1, input: 1200, output: 300, cached: 800),
                        Fixture.codexTokens(ordinal: 2, input: 1200, output: 300, cached: 800),
                        Fixture.codexTokens(ordinal: 3, input: 2500, output: 410, cached: 2000)], append: true)
        codex.poll(into: out.pipeline)
        let usage = out.events.compactMap(\.usage)
        #expect(usage == [AgentUsage(inputTokens: 1200, outputTokens: 300, cachedInputTokens: 800),
                          AgentUsage(inputTokens: 2500, outputTokens: 410, cachedInputTokens: 2000)])
    }

    @Test func truncatedFileIsReadAgainWithoutDuplicates() throws {
        let home = try Fixture.temporaryDirectory()
        let file = Fixture.codexRollout(home, id: a)
        try file.write([Fixture.codexMeta(id: a, cwd: "/work/alpha")])
        let out = Collected()
        let codex = monitor(home)
        codex.poll(into: out.pipeline)
        out.pipeline.flushReplay()
        try file.write([Fixture.codexEvent("task_started", ordinal: 1),
                        Fixture.codexComplete(ordinal: 2)], append: true)
        codex.poll(into: out.pipeline)

        // Файл переписан короче: тот же заголовок и новая строка.
        try file.write([Fixture.codexMeta(id: a, cwd: "/work/alpha"),
                        Fixture.codexEvent("task_started", ordinal: 1, at: "2026-10-25T17:10:00.000Z")])
        codex.poll(into: out.pipeline)
        #expect(out.kinds(a) == [.sessionStarted, .working, .turnCompleted])

        try file.write([Fixture.codexEvent("task_complete", ordinal: 7)], append: true)
        codex.poll(into: out.pipeline)
        #expect(out.kinds(a).last == .turnCompleted)
        #expect(Set(out.events.map(\.eventID)).count == out.events.count)
    }

    @Test func interruptedTurnWaitsAndUnknownErrorIsFailure() throws {
        let home = try Fixture.temporaryDirectory()
        let file = Fixture.codexRollout(home, id: a)
        try file.write([Fixture.codexMeta(id: a, cwd: "/work/alpha")])
        let out = Collected()
        let codex = monitor(home)
        codex.poll(into: out.pipeline)
        out.pipeline.flushReplay()
        try file.write([Fixture.codexEvent("task_started", ordinal: 1),
                        Fixture.codexEvent("turn_aborted", ordinal: 2, extra: ["reason": "interrupted"]),
                        Fixture.codexEvent("error", ordinal: 3, extra: ["message": Fixture.secret])], append: true)
        codex.poll(into: out.pipeline)
        #expect(out.kinds(a) == [.sessionStarted, .working, .waiting, .failed])
        #expect(!out.lines.contains(Fixture.secret))
    }

    @Test func auxiliaryThreadsAreSkipped() throws {
        let home = try Fixture.temporaryDirectory()
        let file = Fixture.codexRollout(home, id: a)
        try file.write([Fixture.codexMeta(id: a, cwd: "/work/alpha", subagent: true),
                        Fixture.codexEvent("task_started", ordinal: 1)])
        let out = Collected()
        let codex = monitor(home)
        codex.poll(into: out.pipeline)
        out.pipeline.flushReplay()
        try file.write([Fixture.codexComplete(ordinal: 2)], append: true)
        codex.poll(into: out.pipeline)
        #expect(out.events.isEmpty)
    }

    @Test func vanishedFileDisconnectsInsteadOfEnding() throws {
        let home = try Fixture.temporaryDirectory()
        let file = Fixture.codexRollout(home, id: a)
        try file.write([Fixture.codexMeta(id: a, cwd: "/work/alpha"),
                        Fixture.codexEvent("task_started", ordinal: 1)])
        let out = Collected()
        let codex = monitor(home)
        codex.poll(into: out.pipeline)
        out.pipeline.flushReplay()
        try FileManager.default.removeItem(at: file)
        codex.poll(into: out.pipeline)
        #expect(out.kinds(a) == [.sessionStarted, .working, .disconnected])
    }

    @Test func newSessionInTodaysFolderIsSeenWithoutFullScan() throws {
        let home = try Fixture.temporaryDirectory()
        let out = Collected()
        let codex = monitor(home, fullScanEvery: 1_000)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("sessions"),
                                                withIntermediateDirectories: true)
        codex.poll(into: out.pipeline)
        out.pipeline.flushReplay()
        try Fixture.codexRollout(home, id: a).write([Fixture.codexMeta(id: a, cwd: "/work/alpha"),
                                                     Fixture.codexEvent("task_started", ordinal: 1)])
        codex.poll(into: out.pipeline)
        #expect(out.kinds(a) == [.sessionStarted, .working])
    }

    @Test func malformedAndOversizedLinesDoNotBreakReading() throws {
        let home = try Fixture.temporaryDirectory()
        let file = Fixture.codexRollout(home, id: a)
        let huge = Fixture.json(["timestamp": "2026-10-25T17:00:05.000Z", "ordinal": 2, "type": "event_msg",
                                 "payload": ["type": "task_complete", "turn_id": "t",
                                             "last_agent_message": String(repeating: "x", count: 1_200_000)]])
        try file.write([Fixture.codexMeta(id: a, cwd: "/work/alpha"),
                        "{not json", "", "[1,2,3]", "\u{0}\u{1}garbage",
                        Fixture.codexEvent("task_started", ordinal: 1), huge,
                        Fixture.codexEvent("task_started", ordinal: 3)])
        let out = Collected()
        let codex = monitor(home)
        codex.poll(into: out.pipeline)
        out.pipeline.flushReplay()
        // Снимок: начало и последнее состояние — новый ход после огромной строки.
        #expect(out.kinds(a) == [.sessionStarted, .working])
        #expect(out.events.last?.eventID == "codex:\(a):3")
    }

    @Test func oldFilesAreFollowedButNotReplayed() throws {
        let home = try Fixture.temporaryDirectory()
        let file = Fixture.codexRollout(home, id: a, day: "2026/09/01")
        try file.write([Fixture.codexMeta(id: a, cwd: "/work/alpha"), Fixture.codexComplete(ordinal: 1)])
        let old = Date().addingTimeInterval(-3 * 24 * 3600)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: file.path)
        let out = Collected()
        let codex = monitor(home, fullScanEvery: 3)
        codex.poll(into: out.pipeline)
        out.pipeline.flushReplay()
        #expect(out.events.isEmpty)
        // Нить продолжили в Desktop — дописывание в тот же файл. Старый
        // каталог виден только при полном обходе: третий опрос.
        try file.write([Fixture.codexEvent("task_started", ordinal: 2)], append: true)
        codex.poll(into: out.pipeline)
        #expect(out.events.isEmpty)
        codex.poll(into: out.pipeline)
        #expect(out.kinds(a) == [.sessionStarted, .working])
        #expect(out.events.first?.projectPath == "/work/alpha")
    }
}
