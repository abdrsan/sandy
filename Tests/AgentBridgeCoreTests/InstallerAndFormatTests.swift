import Foundation
import Testing
@testable import AgentBridgeCore

struct ClaudeSettingsInstallerTests {
    let helper = "/Applications/Sandy.app/Contents/Helpers/sandy-agent"

    private func settingsFile(_ text: String?) throws -> URL {
        let dir = try Fixture.temporaryDirectory()
        let file = dir.appendingPathComponent("settings.json")
        if let text { try Data(text.utf8).write(to: file) }
        return file
    }

    private func load(_ file: URL) throws -> JSONObject {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? JSONObject)
    }

    private let userSettings = """
    {"model":"opus","env":{"API_KEY":"keep-me"},
     "hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/usr/local/bin/guard.sh"}]}],
              "Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}
    """

    @Test func installMergesBacksUpAndIsIdempotent() throws {
        let file = try settingsFile(userSettings)
        let outcome = try ClaudeSettingsInstaller.install(settingsURL: file, executable: helper)
        #expect(outcome.changed)
        let backup = try #require(outcome.backup)
        #expect(try String(contentsOf: backup, encoding: .utf8) == userSettings)

        let settings = try load(file)
        #expect(settings.string("model") == "opus")
        #expect(settings.object("env")?.string("API_KEY") == "keep-me")
        let hooks = try #require(settings.object("hooks"))
        for hook in ClaudeSettingsInstaller.hooks {
            #expect(hooks.array(hook.event) != nil, "нет \(hook.event)")
        }
        #expect((hooks.array("PreToolUse")?.count) == 2)
        #expect((hooks.array("Stop")?.count) == 2)

        let again = try ClaudeSettingsInstaller.install(settingsURL: file, executable: helper)
        #expect(!again.changed)
        #expect(again.backup == nil)
        #expect(try load(file).object("hooks")?.array("PreToolUse")?.count == 2)
    }

    @Test func movedAppReplacesOldEntryInsteadOfDuplicating() throws {
        let file = try settingsFile(userSettings)
        _ = try ClaudeSettingsInstaller.install(settingsURL: file, executable: "/tmp/Old Place/Sandy.app/Contents/Helpers/sandy-agent")
        let moved = try ClaudeSettingsInstaller.install(settingsURL: file, executable: helper)
        #expect(moved.removedHandlers == ClaudeSettingsInstaller.hooks.count)
        let pre = try #require(try load(file).object("hooks")?.array("PreToolUse"))
        #expect(pre.count == 2)
        #expect(Fixture.json(["x": pre]).contains("/Applications/Sandy.app"))
        #expect(!Fixture.json(["x": pre]).contains("Old Place"))
    }

    @Test func uninstallRemovesOnlySandyEntries() throws {
        let file = try settingsFile(userSettings)
        _ = try ClaudeSettingsInstaller.install(settingsURL: file, executable: helper)
        let outcome = try ClaudeSettingsInstaller.uninstall(settingsURL: file)
        #expect(outcome.removedHandlers == ClaudeSettingsInstaller.hooks.count)
        #expect(outcome.backup != nil)
        let original = try #require(JSONSerialization.jsonObject(with: Data(userSettings.utf8)) as? NSDictionary)
        #expect(try load(file) as NSDictionary == original)
        #expect(!(try ClaudeSettingsInstaller.uninstall(settingsURL: file).changed))
    }

    @Test func groupSharedWithForeignHandlerKeepsForeignHandler() throws {
        let command = ClaudeSettingsInstaller.command(executable: helper)
        let text = Fixture.json(["hooks": ["Stop": [["hooks": [
            ["type": "command", "command": command],
            ["type": "command", "command": "say done"]]]]]])
        let file = try settingsFile(text)
        _ = try ClaudeSettingsInstaller.uninstall(settingsURL: file)
        let stop = try #require(try load(file).object("hooks")?.array("Stop") as? [JSONObject])
        #expect(stop.count == 1)
        #expect((stop[0]["hooks"] as? [Any])?.count == 1)
    }

    @Test func freshInstallWithoutSettingsCreatesFileWithoutBackup() throws {
        let file = try settingsFile(nil)
        let outcome = try ClaudeSettingsInstaller.install(settingsURL: file, executable: helper)
        #expect(outcome.changed && outcome.backup == nil)
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        #expect(try ClaudeSettingsInstaller.uninstall(settingsURL: file).changed)
    }

    @Test func unreadableSettingsAreNeverOverwritten() throws {
        for text in ["{\"hooks\": [1,2]", "[1,2]", "{\"hooks\": 5}"] {
            let file = try settingsFile(text)
            #expect(throws: ClaudeSettingsInstaller.InstallError.self) {
                try ClaudeSettingsInstaller.install(settingsURL: file, executable: helper)
            }
            #expect(try String(contentsOf: file, encoding: .utf8) == text)
        }
    }

    /// The installed command, run through the same `sh -c` Claude Code uses.
    @Test func installedCommandRunsHelperAndIsSilentWhenHelperIsGone() throws {
        let dir = try Fixture.temporaryDirectory()
        let helper = dir.appendingPathComponent("it's here/sandy-agent")
        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let marker = dir.appendingPathComponent("ran")
        try Data("#!/bin/sh\necho \"$1\" > '\(marker.path)'\n".utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        let command = ClaudeSettingsInstaller.command(executable: helper.path)

        func run() throws -> Int32 {
            let shell = Process()
            shell.executableURL = URL(fileURLWithPath: "/bin/sh")
            shell.arguments = ["-c", command]
            try shell.run()
            shell.waitUntilExit()
            return shell.terminationStatus
        }
        #expect(try run() == 0)
        #expect(try String(contentsOf: marker, encoding: .utf8) == "claude-hook\n")
        try FileManager.default.removeItem(at: helper)
        #expect(try run() == 0)
    }

    @Test func dryRunDoesNotWrite() throws {
        let file = try settingsFile(userSettings)
        let outcome = try ClaudeSettingsInstaller.install(settingsURL: file, executable: helper, dryRun: true)
        #expect(outcome.changed)
        #expect(try String(contentsOf: file, encoding: .utf8) == userSettings)
    }

    @Test func commandIsShellQuotedAndRecognised() {
        let tricky = "/Users/o'brien/Apps/Sandy $HOME.app/Contents/Helpers/sandy-agent"
        let command = ClaudeSettingsInstaller.command(executable: tricky)
        let quoted = "'/Users/o'\\''brien/Apps/Sandy $HOME.app/Contents/Helpers/sandy-agent'"
        #expect(command == "[ ! -x \(quoted) ] || \(quoted) claude-hook")
        #expect(ClaudeSettingsInstaller.isSandyCommand(command))
        #expect(ClaudeSettingsInstaller.isSandyCommand("\(quoted) claude-hook"))
        #expect(!ClaudeSettingsInstaller.isSandyCommand("/usr/bin/other claude-hook"))
        #expect(!ClaudeSettingsInstaller.isSandyCommand("sandy-agent monitor"))
    }
}

struct EventFormatTests {
    @Test func eventLineMatchesContract() throws {
        let event = AgentEvent(
            eventID: "codex:abc:5", source: .codex, sessionID: "abc",
            timestamp: try #require(AgentTimestamp.parse("2026-10-25T18:00:00.123456Z")),
            kind: .working, projectPath: "/work/p", operation: OperationLabels.runCommand,
            usage: AgentUsage(inputTokens: 1200, outputTokens: nil))
        let object = try #require(JSONSerialization.jsonObject(with: event.jsonLine()) as? JSONObject)
        #expect(object.int("schema_version") == 1)
        #expect(object.string("timestamp") == "2026-10-25T18:00:00.123Z")
        #expect(object.string("kind") == "working")
        #expect(object["error"] == nil && object["tool"] == nil)
        #expect(object.object("usage")?.int("input_tokens") == 1200)
        #expect(object.object("usage")?["output_tokens"] == nil)
        #expect(!String(decoding: event.jsonLine(), as: UTF8.self).contains("\n"))
    }

    @Test func pipelineDropsDuplicateIDsAndRepeatedStates() {
        let out = Collected()
        let base = Date(timeIntervalSince1970: 1_790_000_000)
        func ev(_ id: String, _ kind: AgentEventKind, op: String? = nil) -> AgentEvent {
            AgentEvent(eventID: id, source: .claude, sessionID: "s", timestamp: base, kind: kind, operation: op)
        }
        out.pipeline.emit(ev("1", .sessionStarted))
        out.pipeline.emit(ev("1", .sessionStarted))
        out.pipeline.emit(ev("2", .working, op: "A"))
        out.pipeline.emit(ev("3", .working, op: "A"))
        out.pipeline.emit(ev("4", .working, op: "B"))
        out.pipeline.emit(ev("5", .turnCompleted))
        out.pipeline.emit(ev("6", .turnCompleted))
        #expect(out.events.map(\.eventID) == ["1", "2", "4", "5", "6"])
    }

    @Test func tailReaderHandlesCRLFAndSplitUTF8() throws {
        let dir = try Fixture.temporaryDirectory()
        let file = dir.appendingPathComponent("x.jsonl")
        let line = Data("{\"t\":\"привет\"}\r\n".utf8)
        try line.prefix(9).write(to: file)
        let reader = JSONLTailReader(path: file.path)
        #expect(try reader.read().items.isEmpty)
        let handle = try FileHandle(forWritingTo: file)
        handle.seekToEndOfFile()
        handle.write(line.dropFirst(9))
        try handle.close()
        let items = try reader.read().items
        #expect(items == [.line(Data("{\"t\":\"привет\"}".utf8), offset: 0)])
    }

    @Test func tailReaderBoundsEachRead() throws {
        let dir = try Fixture.temporaryDirectory()
        let file = dir.appendingPathComponent("x.jsonl")
        try Data(String(repeating: "{\"a\":1}\n", count: 10_000).utf8).write(to: file)
        let reader = JSONLTailReader(path: file.path, maxLineBytes: 1024, maxReadBytes: 4096)
        var total = 0
        var reads = 0
        while true {
            let batch = try reader.read()
            total += batch.items.count
            reads += 1
            if !batch.hasMore { break }
        }
        #expect(total == 10_000)
        #expect(reads == 20)
    }
}
