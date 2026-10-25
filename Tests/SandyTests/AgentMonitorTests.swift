import Foundation
import Testing
@testable import Sandy

@MainActor
private final class MonitorTestBridge: AgentBridgeRunning {
    var onData: ((Data) -> Void)?
    var onExit: ((Int32) -> Void)?
    var starts: [[String]] = []
    var stopCount = 0
    var launchError: Error?

    func start(arguments: [String]) throws {
        starts.append(arguments)
        if let launchError { throw launchError }
    }

    func stop() { stopCount += 1 }
    func emit(_ data: Data) { onData?(data) }
    func exit(_ code: Int32 = 0) { onExit?(code) }
}

@MainActor
private final class MonitorTestNotifications: AgentNotificationDelivering {
    var onOpen: ((String) -> Void)?
    var permissionRequests = 0
    var authorizationReads = 0
    var cancelCount = 0
    var alerts: [AgentAlert] = []
    var permissionResult = true
    var currentAuthorization: AgentNotificationAuthorization = .allowed
    var suspendPermission = false
    var permissionContinuation: CheckedContinuation<Bool, Never>?

    func requestPermission() async -> Bool {
        permissionRequests += 1
        if suspendPermission {
            return await withCheckedContinuation { permissionContinuation = $0 }
        }
        return permissionResult
    }

    func authorization() async -> AgentNotificationAuthorization {
        authorizationReads += 1
        return currentAuthorization
    }

    func post(_ alert: AgentAlert) { alerts.append(alert) }
    func cancelPending() { cancelCount += 1 }
}

/// The real settings, providers, hooks and notification center are never used.
@MainActor
struct AgentMonitorTests {
    private func temporaryFolder() throws -> URL {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("sandy-agent-monitor-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func makeStore(
        in folder: URL,
        preferences: AgentMonitorPreferences = AgentMonitorPreferences(),
        bridge: MonitorTestBridge,
        notifications: MonitorTestNotifications,
        savePreferences: @escaping (AgentMonitorPreferences) -> Void = { _ in }
    ) -> AgentMonitorStore {
        AgentMonitorStore(file: folder.appendingPathComponent("history.json"), preferences: preferences,
                          bridge: bridge, notifications: notifications,
                          executable: folder.appendingPathComponent("unused-helper"),
                          observeWorkspace: false, savePreferences: savePreferences)
    }

    private func event(
        _ id: String, kind: String = "working", source: String = "codex", session: String = "a",
        at time: Date, newline: Bool = true, usage: [String: Int]? = nil
    ) throws -> Data {
        let date = ISO8601DateFormatter()
        date.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var value: [String: Any] = [
            "schema_version": 1, "event_id": id, "source": source, "session_id": session,
            "timestamp": date.string(from: time), "kind": kind,
            "project_path": "/temporary/test-project", "operation": "Read file"
        ]
        if let usage { value["usage"] = usage }
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return newline ? data + Data([0x0A]) : data
    }

    private func yieldUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            await Task.yield()
        }
        return condition()
    }

    @Test func monitoringDefaultsOffAndStartupNeverRequestsNotificationPermission() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let bridge = MonitorTestBridge()
        let notifications = MonitorTestNotifications()
        let store = makeStore(in: folder, bridge: bridge, notifications: notifications)
        defer { store.stop() }

        #expect(store.preferences.monitoringEnabled == false)
        #expect(store.preferences.notificationsEnabled == false)
        store.start()
        #expect(await yieldUntil { notifications.authorizationReads > 0 })
        #expect(store.connection == .stopped)
        #expect(bridge.starts.isEmpty)
        #expect(notifications.permissionRequests == 0)
        #expect(notifications.alerts.isEmpty)
        #expect(store.sessions.isEmpty)
    }

    @Test func enabledSourcesDetermineArgumentsAndFilterEvents() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let bridge = MonitorTestBridge()
        let notifications = MonitorTestNotifications()
        var preferences = AgentMonitorPreferences()
        preferences.monitoringEnabled = true
        preferences.claudeEnabled = false
        let store = makeStore(in: folder, preferences: preferences, bridge: bridge, notifications: notifications)
        defer { store.stop() }
        let now = Date().addingTimeInterval(-5)

        store.start()
        #expect(bridge.starts.last == ["monitor", "--codex"])
        #expect(store.connection == .running)
        bridge.emit(try event("claude-disabled", source: "claude", at: now))
        bridge.emit(try event("codex-enabled", at: now))
        #expect(store.sessions.map(\.id) == ["codex:a"])
        let stopsBeforeSourceChange = bridge.stopCount
        store.setSource(.claude, enabled: true)
        #expect(bridge.stopCount > stopsBeforeSourceChange)
        #expect(bridge.starts.last == ["monitor", "--claude", "--codex"])
        store.setSource(.codex, enabled: false)
        #expect(bridge.starts.last == ["monitor", "--claude"])
        bridge.emit(try event("codex-now-disabled", session: "b", at: now.addingTimeInterval(1)))
        bridge.emit(try event("claude-now-enabled", source: "claude", at: now.addingTimeInterval(1)))
        #expect(Set(store.sessions.map(\.id)) == ["codex:a", "claude:a"])
        store.setSource(.claude, enabled: false)
        #expect(store.connection == .stopped)
        #expect(store.sessions.allSatisfy { $0.state == .disconnected })
    }

    @Test func hidingPanelAndDisablingMonitorStopWorkAndShowingPanelRestarts() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let bridge = MonitorTestBridge()
        let notifications = MonitorTestNotifications()
        var preferences = AgentMonitorPreferences()
        preferences.monitoringEnabled = true
        let store = makeStore(in: folder, preferences: preferences, bridge: bridge, notifications: notifications)
        defer { store.stop() }
        let now = Date().addingTimeInterval(-2)

        store.start()
        bridge.emit(try event("working", at: now))
        #expect(store.activeCount == 1)
        store.setPanelEnabled(false)
        let startCountWhileHidden = bridge.starts.count
        #expect(store.connection == .stopped)
        #expect(store.sessions.first?.state == .disconnected)
        bridge.emit(try event("late-ready", kind: "turn_completed", at: now.addingTimeInterval(1)))
        #expect(store.sessions.first?.state == .disconnected)
        store.setPanelEnabled(true)
        #expect(bridge.starts.count == startCountWhileHidden + 1)
        #expect(store.connection == .running)
        store.setMonitoring(false)
        #expect(store.connection == .stopped)
        let startCountWhileDisabled = bridge.starts.count
        store.setPanelEnabled(false)
        store.setPanelEnabled(true)
        #expect(bridge.starts.count == startCountWhileDisabled)
    }

    @Test func splitReadsAndFinalUnterminatedEventAreConsumedBeforeExit() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let bridge = MonitorTestBridge()
        let notifications = MonitorTestNotifications()
        var preferences = AgentMonitorPreferences()
        preferences.monitoringEnabled = true
        preferences.notificationsEnabled = true
        let store = makeStore(in: folder, preferences: preferences, bridge: bridge, notifications: notifications)
        defer { store.stop() }
        let now = Date().addingTimeInterval(0.1)
        let work = try event("working", at: now)
        let split = work.count / 2

        store.start()
        bridge.emit(Data(work.prefix(split)))
        #expect(store.sessions.isEmpty)
        bridge.emit(Data(work.dropFirst(split)))
        #expect(store.sessions.first?.state == .working)
        bridge.emit(try event("ready", kind: "turn_completed", at: now.addingTimeInterval(2), newline: false))
        #expect(store.sessions.first?.state == .working)
        bridge.exit()
        #expect(store.connection == .failed)
        #expect(store.sessions.first?.state == .ready)
        #expect(notifications.alerts.count == 1)
        #expect(notifications.alerts.first?.kind == .ready)
    }

    @Test func unexpectedExitMarksWorkingSessionsDisconnectedWithoutReadyAlert() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let bridge = MonitorTestBridge()
        let notifications = MonitorTestNotifications()
        var preferences = AgentMonitorPreferences()
        preferences.monitoringEnabled = true
        preferences.notificationsEnabled = true
        let store = makeStore(in: folder, preferences: preferences, bridge: bridge, notifications: notifications)
        defer { store.stop() }

        store.start()
        bridge.emit(try event("working", at: Date().addingTimeInterval(-1)))
        bridge.exit(1)
        #expect(store.connection == .failed)
        #expect(store.sessions.first?.state == .disconnected)
        #expect(store.activeCount == 0)
        #expect(notifications.alerts.isEmpty)
        store.retry()
        #expect(store.connection == .running)
        #expect(bridge.starts.count == 2)
    }

    @Test func notificationsRequireExplicitEnableAndDeduplicateTransitions() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let bridge = MonitorTestBridge()
        let notifications = MonitorTestNotifications()
        var preferences = AgentMonitorPreferences()
        preferences.monitoringEnabled = true
        let store = makeStore(in: folder, preferences: preferences, bridge: bridge, notifications: notifications)
        defer { store.stop() }
        let now = Date().addingTimeInterval(0.1)

        store.start()
        bridge.emit(try event("work", at: now))
        bridge.emit(try event("ready-before-opt-in", kind: "turn_completed", at: now.addingTimeInterval(1)))
        #expect(notifications.alerts.isEmpty)
        #expect(notifications.permissionRequests == 0)
        store.setNotifications(true)
        #expect(await yieldUntil { store.preferences.notificationsEnabled })
        #expect(notifications.permissionRequests == 1)
        bridge.emit(try event("work-again", at: now.addingTimeInterval(2)))
        let ready = try event("ready-after-opt-in", kind: "turn_completed", at: now.addingTimeInterval(3))
        bridge.emit(ready)
        bridge.emit(ready)
        bridge.emit(try event("another-ready-envelope", kind: "turn_completed", at: now.addingTimeInterval(4)))
        #expect(notifications.alerts.count == 1)
        #expect(notifications.alerts.first?.sessionID == "codex:a")
        let cancelsBeforeDisabling = notifications.cancelCount
        store.setNotifications(false)
        #expect(notifications.cancelCount == cancelsBeforeDisabling + 1)
        bridge.emit(try event("new-work", at: now.addingTimeInterval(5)))
        bridge.emit(try event("wait-disabled", kind: "waiting", at: now.addingTimeInterval(6)))
        #expect(notifications.alerts.count == 1)
    }

    @Test func bootstrapHistoryDoesNotNotifyButFreshEventsDo() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let bridge = MonitorTestBridge()
        let notifications = MonitorTestNotifications()
        var preferences = AgentMonitorPreferences()
        preferences.monitoringEnabled = true
        preferences.notificationsEnabled = true
        let store = makeStore(in: folder, preferences: preferences, bridge: bridge, notifications: notifications)
        defer { store.stop() }
        store.start()
        let earlier = Date().addingTimeInterval(-30)
        bridge.emit(try event("bootstrap-work", at: earlier))
        bridge.emit(try event("bootstrap-ready", kind: "turn_completed", at: earlier.addingTimeInterval(1)))
        #expect(store.sessions.first?.state == .ready)
        #expect(notifications.alerts.isEmpty)
        let fresh = Date().addingTimeInterval(0.1)
        bridge.emit(try event("fresh-work", at: fresh))
        bridge.emit(try event("fresh-ready", kind: "turn_completed", at: fresh.addingTimeInterval(0.1)))
        #expect(notifications.alerts.count == 1)
        #expect(notifications.permissionRequests == 0)
    }

    @Test func disablingNotificationsWhilePermissionIsPendingWins() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let bridge = MonitorTestBridge()
        let notifications = MonitorTestNotifications()
        notifications.suspendPermission = true
        let store = makeStore(in: folder, bridge: bridge, notifications: notifications)
        defer { store.stop() }

        store.setNotifications(true)
        #expect(await yieldUntil { notifications.permissionContinuation != nil })
        store.setNotifications(false)
        notifications.permissionContinuation?.resume(returning: true)
        notifications.permissionContinuation = nil
        for _ in 0..<10 { await Task.yield() }
        #expect(store.preferences.notificationsEnabled == false)
        #expect(notifications.cancelCount == 1)
    }

    @Test func userActionsPersistPreferencesWithoutImplicitPermissionRequest() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let bridge = MonitorTestBridge()
        let notifications = MonitorTestNotifications()
        var saved: [AgentMonitorPreferences] = []
        let store = makeStore(in: folder, bridge: bridge, notifications: notifications, savePreferences: { saved.append($0) })
        defer { store.stop() }

        store.start()
        store.setMonitoring(true)
        store.setSource(.claude, enabled: false)
        #expect(saved.count == 2)
        #expect(saved[0].monitoringEnabled)
        #expect(saved[1].claudeEnabled == false)
        #expect(notifications.permissionRequests == 0)
        notifications.permissionResult = false
        store.setNotifications(true)
        #expect(await yieldUntil { saved.count == 3 })
        #expect(saved.last?.notificationsEnabled == false)
        notifications.permissionResult = true
        store.setNotifications(true)
        #expect(await yieldUntil { saved.last?.notificationsEnabled == true })
        store.setNotifications(false)
        #expect(saved.last?.notificationsEnabled == false)
        #expect(saved.last?.monitoringEnabled == true)
        #expect(saved.last?.claudeEnabled == false)
    }

    @Test func savedHistoryRestoresCountersAndDedupWithoutCountingOfflineTime() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let bridge = MonitorTestBridge()
        let notifications = MonitorTestNotifications()
        var preferences = AgentMonitorPreferences()
        preferences.monitoringEnabled = true
        preferences.notificationsEnabled = true
        let store = makeStore(in: folder, preferences: preferences, bridge: bridge, notifications: notifications)
        defer { store.stop() }
        let now = Date().addingTimeInterval(-5)
        let work = try event("work", at: now)
        let ready = try event("ready", kind: "turn_completed", at: now.addingTimeInterval(1))
        store.start()
        bridge.emit(work)
        bridge.emit(ready)
        bridge.emit(try event("usage", kind: "usage", at: now.addingTimeInterval(2), usage: ["input_tokens": 150, "output_tokens": 30]))
        store.flush()
        let priorSession = try #require(store.sessions.first)

        let replacementBridge = MonitorTestBridge()
        let replacementNotifications = MonitorTestNotifications()
        let restored = makeStore(in: folder, preferences: preferences, bridge: replacementBridge, notifications: replacementNotifications)
        defer { restored.stop() }
        let restoredSession = try #require(restored.sessions.first)
        #expect(restoredSession.activeSeconds == priorSession.activeSeconds)
        #expect(restoredSession.inputTokens == 150)
        #expect(restoredSession.outputTokens == 30)
        #expect(restoredSession.operations == 1)
        #expect(restoredSession.state == .ready)
        restored.start()
        replacementBridge.emit(work)
        replacementBridge.emit(ready)
        #expect(replacementNotifications.alerts.isEmpty)
        #expect(restored.sessions.first?.operations == 1)
        #expect(restored.sessions.first?.activeSeconds == priorSession.activeSeconds)
        #expect(replacementNotifications.permissionRequests == 0)
    }

    @Test func corruptHistoryIsPreservedAcrossMonitoringFlushAndStop() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("history.json")
        let original = Data("{ invalid history".utf8)
        try original.write(to: file)
        let bridge = MonitorTestBridge()
        let notifications = MonitorTestNotifications()
        let store = makeStore(in: folder, bridge: bridge, notifications: notifications)
        defer { store.stop() }

        #expect(store.historyError)
        store.start()
        store.setMonitoring(true)
        bridge.emit(try event("work", at: Date().addingTimeInterval(-1)))
        store.flush()
        store.stop()
        #expect(try Data(contentsOf: file) == original)
        #expect(store.historyError)
        // A repaired file can be retried without ever overwriting the bad one.
        try JSONEncoder().encode(AgentSessionLedger()).write(to: file)
        store.retry()
        #expect(store.historyError)
        #expect(store.sessions.count == 1)
        // Moving the previous file aside resumes storage without replacing
        // the live sessions collected while history was unreadable.
        try FileManager.default.moveItem(at: file, to: folder.appendingPathComponent("old-history.json"))
        store.retry()
        #expect(store.historyError == false)
        #expect(store.sessions.count == 1)
        store.flush()
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func notificationClickOpensOnlyKnownSession() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let bridge = MonitorTestBridge()
        let notifications = MonitorTestNotifications()
        var preferences = AgentMonitorPreferences()
        preferences.monitoringEnabled = true
        let store = makeStore(in: folder, preferences: preferences, bridge: bridge, notifications: notifications)
        defer { store.stop() }
        var opens = 0
        store.onOpenSession = { opens += 1 }
        store.start()
        bridge.emit(try event("work", at: Date().addingTimeInterval(-1)))

        notifications.onOpen?("codex:missing")
        #expect(opens == 0)
        #expect(store.selectedSessionID == nil)
        notifications.onOpen?("codex:a")
        #expect(opens == 1)
        #expect(store.selectedSessionID == "codex:a")
        let priorNavigation = store.navigationRequest
        notifications.onOpen?("codex:a")
        #expect(opens == 2)
        #expect(store.navigationRequest != priorNavigation)
        notifications.onOpen?("claude:a")
        #expect(opens == 2)
        #expect(store.selectedSessionID == "codex:a")
    }

    @Test func missingHelperIsVisibleAndCanBeRetried() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let bridge = MonitorTestBridge()
        bridge.launchError = AgentBridgeClient.LaunchError.missingHelper
        let notifications = MonitorTestNotifications()
        var preferences = AgentMonitorPreferences()
        preferences.monitoringEnabled = true
        let store = makeStore(in: folder, preferences: preferences, bridge: bridge, notifications: notifications)
        defer { store.stop() }

        store.start()
        #expect(store.connection == .missingHelper)
        #expect(store.sessions.isEmpty)
        bridge.launchError = nil
        store.retry()
        #expect(store.connection == .running)
        #expect(notifications.permissionRequests == 0)
    }

    @Test func realProcessDrainsStdoutAndFinalEventBeforeReportingExit() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let executable = folder.appendingPathComponent("fixture-agent")
        let now = Date().addingTimeInterval(0.1)
        let first = try event("real-working", at: now)
        let last = try event("real-ready", kind: "turn_completed", session: "b", at: now.addingTimeInterval(1), newline: false)
        let split = first.count / 2
        func quote(_ bytes: Data) throws -> String {
            let text = try #require(String(data: bytes, encoding: .utf8))
            return "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        let script = try "#!/bin/sh\nprintf '%s' \(quote(Data(first.prefix(split))))\nprintf '%s' \(quote(Data(first.dropFirst(split))))\nprintf '%s' \(quote(last))\n"
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let bridge = AgentBridgeClient(executable: executable)
        let notifications = MonitorTestNotifications()
        var preferences = AgentMonitorPreferences()
        preferences.monitoringEnabled = true
        preferences.notificationsEnabled = true
        let store = AgentMonitorStore(file: folder.appendingPathComponent("history.json"), preferences: preferences,
                                      bridge: bridge, notifications: notifications, executable: executable,
                                      observeWorkspace: false, savePreferences: { _ in })
        defer { store.stop() }

        store.start()
        for _ in 0..<200 where store.connection == .running {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(store.connection == .failed)
        #expect(store.sessions.count == 2)
        #expect(store.sessions.first(where: { $0.id == "codex:a" })?.state == .disconnected)
        #expect(store.sessions.first(where: { $0.id == "codex:b" })?.state == .ready)
        #expect(notifications.alerts.count == 1)
        #expect(notifications.alerts.first?.sessionID == "codex:b")
        #expect(notifications.permissionRequests == 0)
    }
}
