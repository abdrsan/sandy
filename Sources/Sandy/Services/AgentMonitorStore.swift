import AppKit
import Combine
import Darwin

struct AgentMonitorPreferences: Codable, Equatable, Sendable {
    var monitoringEnabled = false
    var claudeEnabled = true
    var codexEnabled = true
    var notificationsEnabled = false

    init(monitoringEnabled: Bool = false, claudeEnabled: Bool = true,
         codexEnabled: Bool = true, notificationsEnabled: Bool = false) {
        self.monitoringEnabled = monitoringEnabled
        self.claudeEnabled = claudeEnabled
        self.codexEnabled = codexEnabled
        self.notificationsEnabled = notificationsEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case monitoringEnabled, claudeEnabled, codexEnabled, notificationsEnabled
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        monitoringEnabled = try values.decodeIfPresent(Bool.self, forKey: .monitoringEnabled) ?? false
        claudeEnabled = try values.decodeIfPresent(Bool.self, forKey: .claudeEnabled) ?? true
        codexEnabled = try values.decodeIfPresent(Bool.self, forKey: .codexEnabled) ?? true
        notificationsEnabled = try values.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? false
    }

    var sources: Set<AgentSource> {
        Set(AgentSource.allCases.filter { $0 == .claude ? claudeEnabled : codexEnabled })
    }
}

enum AgentConnectionState: Equatable {
    case stopped, starting, running, missingHelper, failed, sleeping
}

@MainActor
final class AgentMonitorStore: ObservableObject {
    @Published private(set) var preferences: AgentMonitorPreferences
    @Published private(set) var connection: AgentConnectionState = .stopped
    @Published private(set) var historyError = false
    @Published private(set) var historyErrorMessage: String?
    @Published private(set) var commandInProgress = false
    @Published private(set) var commandMessage: String?
    @Published private(set) var notificationStatus = localized("Agent notifications are off")
    @Published var selectedSessionID: String?
    @Published private(set) var navigationRequest = UUID()
    @Published private var revision = 0

    var onOpenSession: (() -> Void)?
    var onObservedEvent: ((AgentEvent) -> Void)?
    /// Raised for every alert the ledger emits — completion glow hangs off it.
    var onAlert: ((AgentAlert) -> Void)?
    var onShowSettings: (() -> Void)?

    private var ledger = AgentSessionLedger()
    private let file: URL
    private let bridge: any AgentBridgeRunning
    private let notifications: any AgentNotificationDelivering
    private let executable: URL
    private let savePreferences: (AgentMonitorPreferences) -> Void
    private let writes = DebouncedWrite(after: 0.4)
    private var decoder = AgentJSONLDecoder()
    private var checkpointTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var command: Process?
    private var commandGeneration = 0
    private var authorizationGeneration = 0
    private var started = false
    private var panelEnabled = true
    private var asleep = false
    private var readFailed = false
    private var connectedAt = Date.distantPast

    init(
        file: URL? = nil,
        preferences: AgentMonitorPreferences? = nil,
        bridge: (any AgentBridgeRunning)? = nil,
        notifications: (any AgentNotificationDelivering)? = nil,
        executable: URL = AgentBridgeClient.bundledExecutable,
        observeWorkspace: Bool = true,
        savePreferences: ((AgentMonitorPreferences) -> Void)? = nil
    ) {
        self.file = file ?? Support.file("Agents/history.json")
        self.preferences = preferences ?? ConfigStore.shared.agentMonitor
        self.executable = executable
        self.bridge = bridge ?? AgentBridgeClient(executable: executable)
        self.notifications = notifications ?? AgentNotifications()
        self.savePreferences = savePreferences ?? { ConfigStore.shared.agentMonitor = $0 }
        load()
        self.bridge.onData = { [weak self] in self?.receive($0) }
        self.bridge.onExit = { [weak self] _ in self?.disconnected() }
        self.notifications.onOpen = { [weak self] id in
            guard let self, ledger.sessions[id] != nil else { return }
            selectedSessionID = id
            navigationRequest = UUID()
            onOpenSession?()
        }
        if observeWorkspace {
            let center = NSWorkspace.shared.notificationCenter
            workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.sleep() }
            })
            workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.wake() }
            })
        }
    }

    var sessions: [AgentSession] {
        ledger.sessions.values.sorted {
            if $0.lastEventAt != $1.lastEventAt { return $0.lastEventAt > $1.lastEventAt }
            return $0.id < $1.id
        }
    }

    var summaries: [AgentSummary] { ledger.summaries(at: Date()) }
    var activeCount: Int { sessions.filter { $0.state == .working || $0.state == .waiting }.count }
    func activeDuration(for session: AgentSession, at now: Date) -> TimeInterval { session.activeDuration(at: now) }

    var connectionMessage: String {
        switch connection {
        case .stopped:
            return localized(preferences.monitoringEnabled && preferences.sources.isEmpty ? "No sources selected" : "Monitor is off")
        case .starting: return localized("Starting agent monitor…")
        case .running: return localized("Listening for agent events")
        case .missingHelper: return localized("Agent helper is missing. Rebuild Sandy with sandy-agent.")
        case .failed: return localized("Agent monitor disconnected. Retry to reconnect.")
        case .sleeping: return localized("Monitoring paused during sleep")
        }
    }

    func start() {
        started = true
        reconcile()
        Task { [weak self] in await self?.refreshNotificationStatus() }
    }

    func stop() {
        started = false
        authorizationGeneration += 1
        stopMonitor(state: .stopped)
        commandGeneration += 1
        if let command, command.isRunning { command.terminate() }
        command = nil
        commandInProgress = false
        writes.flush()
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { center.removeObserver($0) }
        workspaceObservers.removeAll()
    }

    func setPanelEnabled(_ enabled: Bool) {
        guard panelEnabled != enabled else { return }
        panelEnabled = enabled
        reconcile()
    }

    func setMonitoring(_ enabled: Bool) {
        preferences.monitoringEnabled = enabled
        savePreferences(preferences)
        reconcile()
    }

    func setSource(_ source: AgentSource, enabled: Bool) {
        if source == .claude { preferences.claudeEnabled = enabled }
        else { preferences.codexEnabled = enabled }
        savePreferences(preferences)
        reconcile()
    }

    /// Only this user-action entry point can request permission.
    func setNotifications(_ enabled: Bool) {
        authorizationGeneration += 1
        let stamp = authorizationGeneration
        if !enabled {
            preferences.notificationsEnabled = false
            savePreferences(preferences)
            notifications.cancelPending()
            notificationStatus = localized("Agent notifications are off")
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let granted = await notifications.requestPermission()
            guard stamp == authorizationGeneration else { return }
            preferences.notificationsEnabled = granted
            savePreferences(preferences)
            await refreshNotificationStatus()
        }
    }

    func showSettings() { onShowSettings?() }
    func showHistoryFile() { NSWorkspace.shared.activateFileViewerSelecting([file]) }
    func refreshNotificationAuthorization() {
        Task { [weak self] in await self?.refreshNotificationStatus() }
    }
    func retry() {
        if readFailed {
            // Loading a repaired snapshot over newly observed sessions would
            // discard those sessions. Keep them until the old file is moved
            // aside; then resume writing the current in-memory history.
            if !ledger.sessions.isEmpty, FileManager.default.fileExists(atPath: file.path) {
                historyErrorMessage = localized("Move the previous history file aside, then Retry. Current sessions will be kept.")
            } else {
                load()
                if !readFailed { scheduleSave() }
            }
        }
        reconcile()
    }
    func installClaudeHooks() { runHookCommand("install-claude-hooks") }
    func uninstallClaudeHooks() { runHookCommand("uninstall-claude-hooks") }
    func installMobileApprovals() { runHookCommand("install-mobile-approvals") }
    func uninstallMobileApprovals() { runHookCommand("uninstall-mobile-approvals") }

    func sleep(at now: Date = Date()) {
        asleep = true
        stopMonitor(state: .sleeping, at: now)
        writes.flush()
    }

    func wake() {
        asleep = false
        reconcile()
    }

    private func reconcile() {
        stopMonitor(state: asleep ? .sleeping : .stopped)
        guard started, panelEnabled, !asleep, preferences.monitoringEnabled, !preferences.sources.isEmpty else { return }
        decoder = AgentJSONLDecoder()
        connection = .starting
        connectedAt = Date()
        let args = ["monitor"] + AgentSource.allCases.filter { preferences.sources.contains($0) }.map { "--\($0.rawValue)" }
        do {
            try bridge.start(arguments: args)
            connection = .running
            checkpointTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkpoint() }
            }
        } catch AgentBridgeClient.LaunchError.missingHelper {
            connection = .missingHelper
        } catch {
            connection = .failed
        }
    }

    private func stopMonitor(state: AgentConnectionState, at now: Date = Date()) {
        bridge.stop()
        notifications.cancelPending()
        checkpointTimer?.invalidate()
        checkpointTimer = nil
        decoder = AgentJSONLDecoder()
        ledger.disconnect(sources: Set(AgentSource.allCases), at: now)
        connection = state
        revision += 1
        scheduleSave()
    }

    private func receive(_ bytes: Data) {
        guard connection == .running else { return }
        apply(decoder.append(bytes))
    }

    private func apply(_ events: [AgentEvent], at now: Date = Date()) {
        guard !events.isEmpty else { return }
        for event in events where preferences.sources.contains(event.source) {
            onObservedEvent?(event)
            // Freshness gate applies to anything user-visible: replayed events
            // on reconnect must not glow or notify for the past.
            if let alert = ledger.ingest(event, receivedAt: now),
               event.timestamp >= connectedAt.addingTimeInterval(-1) {
                onAlert?(alert)
                if preferences.notificationsEnabled {
                    notifications.post(alert)
                }
            }
        }
        ledger.prune(before: now.addingTimeInterval(-30 * 24 * 60 * 60))
        revision += 1
        scheduleSave()
    }

    private func disconnected() {
        guard connection == .running else { return }
        apply(decoder.finish())
        stopMonitor(state: .failed)
        writes.flush()
    }

    private func checkpoint() {
        // Only observed working time moves between events. Without it the
        // whole history was rewritten every 20 seconds for nothing.
        guard ledger.sessions.values.contains(where: { $0.activeSince != nil }) else { return }
        ledger.checkpoint(at: Date())
        revision += 1
        scheduleSave()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: file.path) else {
            readFailed = false
            historyError = false
            historyErrorMessage = nil
            return
        }
        do {
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 16 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
            var restored = try JSONDecoder().decode(AgentSessionLedger.self, from: Data(contentsOf: file))
            guard restored.sessions.allSatisfy({ id, session in
                id == session.id && session.operations >= 0
                    && session.activeSeconds.isFinite && session.activeSeconds >= 0
                    && session.activeSeconds <= 100 * 365 * 24 * 60 * 60
                    && (session.inputTokens.map { $0 >= 0 } ?? true)
                    && (session.outputTokens.map { $0 >= 0 } ?? true)
            }) else { throw CocoaError(.fileReadCorruptFile) }
            restored.restore(at: Date())
            restored.prune(before: Date().addingTimeInterval(-30 * 24 * 60 * 60))
            ledger = restored
            readFailed = false
            historyError = false
            historyErrorMessage = nil
        } catch {
            readFailed = true
            historyError = true
            historyErrorMessage = localized("Agent history could not be read. Existing file was preserved.")
        }
    }

    private func scheduleSave() {
        writes.schedule { [weak self] in self?.persist() }
    }

    func flush() {
        ledger.checkpoint(at: Date())
        persist()
        writes.cancel()
    }

    private func persist() {
        guard !readFailed else { return }
        do {
            let folder = file.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            let data = try encoder.encode(ledger)
            guard data.count <= 16 * 1024 * 1024 else { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            historyError = false
            historyErrorMessage = nil
        } catch {
            historyError = true
            historyErrorMessage = localized("Could not save agent history")
        }
    }

    private func refreshNotificationStatus() async {
        switch await notifications.authorization() {
        case .allowed:
            notificationStatus = localized(preferences.notificationsEnabled ? "Notifications allowed" : "Agent notifications are off")
        case .denied: notificationStatus = localized("Notifications blocked in System Settings")
        case .notDetermined, .unavailable:
            notificationStatus = localized("Notification permission was not granted")
        }
    }

    private func runHookCommand(_ argument: String) {
        guard !commandInProgress else { return }
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            commandMessage = localized("Agent helper is missing. Rebuild Sandy with sandy-agent.")
            return
        }
        let child = Process()
        child.executableURL = executable
        child.arguments = [argument]
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        commandGeneration += 1
        let stamp = commandGeneration
        child.terminationHandler = { [weak self] process in
            let succeeded = process.terminationStatus == 0
            Task { @MainActor in
                guard let self, stamp == self.commandGeneration else { return }
                self.command = nil
                self.commandInProgress = false
                self.commandMessage = localized(succeeded ? (argument.contains("mobile") ? "Done" : (argument == "install-claude-hooks" ? "Claude hooks installed" : "Claude hooks removed")) : "Could not update Claude hooks")
            }
        }
        do {
            commandInProgress = true
            commandMessage = nil
            try child.run()
            command = child
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                guard let self, stamp == commandGeneration, child.isRunning else { return }
                child.terminate()
                commandMessage = localized("Could not update Claude hooks")
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                    if child.isRunning { kill(child.processIdentifier, SIGKILL) }
                }
            }
        } catch {
            commandInProgress = false
            commandMessage = localized("Could not update Claude hooks")
        }
    }
}
