import AppKit

enum PanelOpenBehavior: String, CaseIterable, Codable {
    case hover, click, shortcut
}

enum PanelScale: String, CaseIterable, Codable {
    case compact, regular, large
    var factor: CGFloat {
        switch self { case .compact: 0.9; case .regular: 1; case .large: 1.12 }
    }
}

/// Everything about Sandy that makes sense on somebody else's Mac, in one
/// file next to `snippets.json` and `notes.json` (#67).
///
/// Before this, the same handful of settings each kept their own place and
/// their own copy of "and what if the key isn't there yet": `showOnAllDisplays`
/// in `NotchGeometry`, `saveClipboardImages` in `NotchViewModel`, the privacy
/// sections in `PrivacyMode`, the teleprompter's speed and font size in
/// `TeleprompterStore`, and, freshest, the tab switches from #80. Harmless at
/// four; every new setting was the fifth spelling of the same question.
///
/// **What comes here.** What has meaning on another Mac. Shelf paths (content,
/// not configuration) and calendar overrides (tied to calendar identifiers on
/// this particular Mac) stay in `UserDefaults` — see #67 for the rule.
///
/// **Migration.** No file yet → built once from the old `UserDefaults` keys
/// and written. The old keys are then left alone: rolling back to a build
/// before this one loses a few switches rather than this app carrying two
/// sources of truth for one release (decided in #67).
@MainActor
final class ConfigStore: ObservableObject {
    private struct Teleprompter: Codable, Equatable {
        var speed: Double = 1
        var fontSize: Double = 30
    }

    private struct File: Codable, Equatable {
        var showOnAllDisplays = true
        var saveClipboardImages = true
        var privacy: [String] = []
        var teleprompter = Teleprompter()
        var hiddenTabs: [String] = []
        var tabOrder: [String] = []
        var openBehavior = PanelOpenBehavior.hover.rawValue
        var closeDelay = 0.25
        var panelScale = PanelScale.regular.rawValue
        var accent = "mint"
        var animationsEnabled = true
        var activeProfile = "Custom"
        var onboardingComplete = true
        var fullSizeDrawnNotch = false
        var panelShortcutEnabled = true
        var panelShortcut = PanelShortcut.controlOptionSpace
        var agentMonitor = AgentMonitorPreferences()
        var clipboardPersist = false
        var clipboardLimit = 40
        var clipboardExcludedApps: [String] = []
        var clearOnlyShelfFiles = true
        var agentGlow = true
        var meetingAlerts = false
        var meetingAlertMinutes = 5
        var translateSource = ""
        var translateTarget = ""

        init() {}

        /// Every key optional, falling back to the default above. The
        /// synthesized decoder treats a key it does not find as a broken
        /// file, so the first setting added after release would have turned
        /// every existing `config.json` read-only in one go — the file written
        /// by the previous version simply does not have it.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = File()
            showOnAllDisplays = try c.decodeIfPresent(Bool.self, forKey: .showOnAllDisplays) ?? d.showOnAllDisplays
            saveClipboardImages = try c.decodeIfPresent(Bool.self, forKey: .saveClipboardImages) ?? d.saveClipboardImages
            privacy = try c.decodeIfPresent([String].self, forKey: .privacy) ?? d.privacy
            teleprompter = try c.decodeIfPresent(Teleprompter.self, forKey: .teleprompter) ?? d.teleprompter
            hiddenTabs = try c.decodeIfPresent([String].self, forKey: .hiddenTabs) ?? d.hiddenTabs
            tabOrder = try c.decodeIfPresent([String].self, forKey: .tabOrder) ?? d.tabOrder
            openBehavior = try c.decodeIfPresent(String.self, forKey: .openBehavior) ?? d.openBehavior
            closeDelay = try c.decodeIfPresent(Double.self, forKey: .closeDelay) ?? d.closeDelay
            panelScale = try c.decodeIfPresent(String.self, forKey: .panelScale) ?? d.panelScale
            accent = try c.decodeIfPresent(String.self, forKey: .accent) ?? d.accent
            animationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .animationsEnabled) ?? d.animationsEnabled
            activeProfile = try c.decodeIfPresent(String.self, forKey: .activeProfile) ?? d.activeProfile
            onboardingComplete = try c.decodeIfPresent(Bool.self, forKey: .onboardingComplete) ?? d.onboardingComplete
            fullSizeDrawnNotch = try c.decodeIfPresent(Bool.self, forKey: .fullSizeDrawnNotch) ?? d.fullSizeDrawnNotch
            panelShortcutEnabled = try c.decodeIfPresent(Bool.self, forKey: .panelShortcutEnabled) ?? d.panelShortcutEnabled
            let shortcut = try c.decodeIfPresent(String.self, forKey: .panelShortcut)
            panelShortcut = shortcut.flatMap(PanelShortcut.init(rawValue:)) ?? d.panelShortcut
            agentMonitor = try c.decodeIfPresent(AgentMonitorPreferences.self, forKey: .agentMonitor) ?? d.agentMonitor
            clipboardPersist = try c.decodeIfPresent(Bool.self, forKey: .clipboardPersist) ?? d.clipboardPersist
            clipboardLimit = try c.decodeIfPresent(Int.self, forKey: .clipboardLimit) ?? d.clipboardLimit
            clipboardExcludedApps = try c.decodeIfPresent([String].self, forKey: .clipboardExcludedApps) ?? d.clipboardExcludedApps
            clearOnlyShelfFiles = try c.decodeIfPresent(Bool.self, forKey: .clearOnlyShelfFiles) ?? d.clearOnlyShelfFiles
            agentGlow = try c.decodeIfPresent(Bool.self, forKey: .agentGlow) ?? d.agentGlow
            meetingAlerts = try c.decodeIfPresent(Bool.self, forKey: .meetingAlerts) ?? d.meetingAlerts
            meetingAlertMinutes = try c.decodeIfPresent(Int.self, forKey: .meetingAlertMinutes) ?? d.meetingAlertMinutes
            translateSource = try c.decodeIfPresent(String.self, forKey: .translateSource) ?? d.translateSource
            translateTarget = try c.decodeIfPresent(String.self, forKey: .translateTarget) ?? d.translateTarget
        }
    }

    static let shared = ConfigStore()

    /// `~/Library/Application Support/Sandy/config.json`.
    static let file = Support.file("config.json")

    /// True when the file exists but cannot be parsed — same meaning and the
    /// same consequence as `SnippetStore.fileBroken` (#7): reading stays
    /// honest, and writing stops rather than paving over a hand edit gone
    /// wrong.
    @Published private(set) var fileBroken = false
    @Published private(set) var onboardingComplete = true
    @Published private(set) var openBehavior = PanelOpenBehavior.hover
    @Published private(set) var panelScale = PanelScale.regular
    @Published private(set) var accent = "mint"
    @Published private(set) var animationsEnabled = true
    @Published private(set) var closeDelay = 0.25

    private var value: File

    private init() {
        if let data = try? Data(contentsOf: Self.file) {
            do {
                value = try JSONDecoder().decode(File.self, from: data)
            } catch {
                value = File()
                fileBroken = true
                NSLog("Sandy: config.json is not readable: \(error.localizedDescription)")
            }
        } else {
            // Nothing on disk yet, so nothing to protect — assembled from
            // whatever the old keys already say and written straight away.
            value = Self.migrated()
            value.onboardingComplete = false
            write(value)
        }
        onboardingComplete = value.onboardingComplete
        openBehavior = PanelOpenBehavior(rawValue: value.openBehavior) ?? .hover
        panelScale = PanelScale(rawValue: value.panelScale) ?? .regular
        accent = value.accent
        animationsEnabled = value.animationsEnabled
        closeDelay = value.closeDelay
    }

    // MARK: - Settings

    /// Persisted switch for every display past the first. Defaults to on: the
    /// panel is meant to be wherever the pointer is, so this is the way to
    /// pull it back to one screen, not the way to ask for the rest.
    var showOnAllDisplays: Bool {
        get { value.showOnAllDisplays }
        set { value.showOnAllDisplays = newValue; persist() }
    }

    /// Brings back the notch drawn the full height of the menu bar on displays
    /// without a cutout. Off by default: see `NotchGeometry.collapsedDepth`.
    var fullSizeDrawnNotch: Bool {
        get { value.fullSizeDrawnNotch }
        set { value.fullSizeDrawnNotch = newValue; persist() }
    }

    /// Off switch for people who copy images all day and do not want them
    /// kept. Defaults to on: the feature is the reason the folder exists.
    var saveClipboardImages: Bool {
        get { value.saveClipboardImages }
        set { value.saveClipboardImages = newValue; persist() }
    }

    /// Raw `PrivacyMode.Section` values. Kept as strings here rather than that
    /// type so this store does not need to know about it — the same reason
    /// `hiddenTabs` below is `[String]` and not `[NotchViewModel.Tab]`.
    var privacy: [String] {
        get { value.privacy }
        set { value.privacy = newValue; persist() }
    }

    var teleprompterSpeed: Double {
        get { value.teleprompter.speed }
        set { value.teleprompter.speed = newValue; persist() }
    }

    var teleprompterFontSize: Double {
        get { value.teleprompter.fontSize }
        set { value.teleprompter.fontSize = newValue; persist() }
    }

    /// Tabs switched off in Settings (#80), by `Tab.rawValue`. Kept as the set
    /// of what is off rather than what is on, so a tab added in a later
    /// version shows up for everyone instead of arriving hidden.
    var hiddenTabs: [String] {
        get { value.hiddenTabs }
        set { value.hiddenTabs = newValue; persist() }
    }

    var tabOrder: [String] {
        get { value.tabOrder }
        set { value.tabOrder = newValue; persist() }
    }

    var closeDelayValue: Double {
        get { value.closeDelay }
        set {
            value.closeDelay = min(2, max(0, newValue))
            closeDelay = value.closeDelay
            persist()
            NotificationCenter.default.post(name: NotchGeometry.settingsChanged, object: nil)
        }
    }

    func setOpenBehavior(_ behavior: PanelOpenBehavior) {
        value.openBehavior = behavior.rawValue
        openBehavior = behavior
        persist()
        NotificationCenter.default.post(name: NotchGeometry.settingsChanged, object: nil)
    }

    func setPanelScale(_ scale: PanelScale) {
        value.panelScale = scale.rawValue
        panelScale = scale
        persist()
        NotificationCenter.default.post(name: NotchGeometry.settingsChanged, object: nil)
    }

    func setAccent(_ color: String) {
        value.accent = color
        accent = color
        persist()
        objectWillChange.send()
    }

    func setAnimationsEnabled(_ enabled: Bool) {
        value.animationsEnabled = enabled
        animationsEnabled = enabled
        persist()
    }

    func applyProfile(_ name: String) {
        let profile: [NotchViewModel.Tab]
        switch name {
        case "Work": profile = [.agents, .clipboard, .notes, .snippets, .calendar, .settings]
        case "Meetings": profile = [.calendar, .notes, .translate, .agents, .settings]
        case "Focus": profile = [.media, .teleprompter, .notes, .settings]
        default: return
        }
        value.hiddenTabs = NotchViewModel.Tab.allCases.filter { $0.canHide && !profile.contains($0) }.map(\.rawValue)
        value.tabOrder = profile.map(\.rawValue)
        value.activeProfile = name
        persist()
        NotificationCenter.default.post(name: .sandyApplyProfile, object: nil)
    }

    var activeProfile: String { value.activeProfile }

    func markProfileCustom() {
        guard value.activeProfile != "Custom" else { return }
        value.activeProfile = "Custom"
        persist()
    }

    func completeOnboarding() {
        guard !onboardingComplete else { return }
        value.onboardingComplete = true
        onboardingComplete = true
        persist()
    }

    var agentMonitor: AgentMonitorPreferences {
        get { value.agentMonitor }
        set { value.agentMonitor = newValue; persist() }
    }

    /// Off by default: a history that survives relaunches has to be asked for.
    /// Turning it off also deletes the file — keeping it would quietly leave
    /// yesterday's clipboard on disk, which is not what "off" means.
    var clipboardPersist: Bool {
        get { value.clipboardPersist }
        set {
            value.clipboardPersist = newValue
            persist()
            if !newValue {
                try? FileManager.default.removeItem(at: Support.file("clipboard.json"))
            }
        }
    }

    var clipboardLimit: Int {
        get { value.clipboardLimit }
        set { value.clipboardLimit = max(1, newValue); persist() }
    }

    /// Bundle identifiers of apps whose copies never enter history — for the
    /// password managers that forget the concealed marker.
    var clipboardExcludedApps: [String] {
        get { value.clipboardExcludedApps }
        set { value.clipboardExcludedApps = newValue; persist() }
    }

    /// On: «Clear» trashes only the vault files that are on the shelf right
    /// now. Off: the whole folder. Default on — the folder is the user's, and
    /// something they dropped into it by hand is not Sandy's to delete.
    var clearOnlyShelfFiles: Bool {
        get { value.clearOnlyShelfFiles }
        set { value.clearOnlyShelfFiles = newValue; persist() }
    }

    /// The notch lights up briefly when an agent finishes a response.
    var agentGlow: Bool {
        get { value.agentGlow }
        set { value.agentGlow = newValue; persist() }
    }

    var meetingAlerts: Bool {
        get { value.meetingAlerts }
        set { value.meetingAlerts = newValue; persist() }
    }

    var meetingAlertMinutes: Int {
        get { value.meetingAlertMinutes }
        set { value.meetingAlertMinutes = max(1, newValue); persist() }
    }

    /// Language identifiers for the translator; empty means route by script.
    var translateSource: String {
        get { value.translateSource }
        set { value.translateSource = newValue; persist() }
    }

    var translateTarget: String {
        get { value.translateTarget }
        set { value.translateTarget = newValue; persist() }
    }

    var panelShortcutEnabled: Bool {
        get { value.panelShortcutEnabled }
        set { value.panelShortcutEnabled = newValue; persist() }
    }

    var panelShortcut: PanelShortcut {
        get { value.panelShortcut }
        set { value.panelShortcut = newValue; persist() }
    }

    // MARK: - Migration

    /// Reads the five places these settings used to live. Each guard mirrors
    /// exactly what that setting's own `object(forKey:) != nil` check used to
    /// do, so a Mac with none of these keys set gets the same defaults as
    /// before and a Mac with some of them set keeps exactly those.
    private static func migrated() -> File {
        let defaults = UserDefaults.standard
        var file = File()
        if defaults.object(forKey: "showOnAllDisplays") != nil {
            file.showOnAllDisplays = defaults.bool(forKey: "showOnAllDisplays")
        }
        if defaults.object(forKey: "saveClipboardImages") != nil {
            file.saveClipboardImages = defaults.bool(forKey: "saveClipboardImages")
        }
        if let sections = defaults.array(forKey: "privacyMode.sections") as? [String] {
            file.privacy = sections
        } else if defaults.bool(forKey: "privacyMode") {
            // The legacy switch covered everything or nothing — see
            // `PrivacyMode.init` before this store existed.
            file.privacy = ["clipboard", "snippets", "calendar", "notes"]
        }
        if let speed = defaults.object(forKey: "teleprompter.speed") as? Double {
            file.teleprompter.speed = speed
        }
        if let fontSize = defaults.object(forKey: "teleprompter.fontSize") as? Double {
            file.teleprompter.fontSize = fontSize
        }
        if let hidden = defaults.stringArray(forKey: "hiddenTabs") {
            file.hiddenTabs = hidden
        }
        return file
    }

    // MARK: - Storage

    private func persist() {
        // Settings panes read through `shared`: the published change is what
        // makes a flipped row redraw.
        objectWillChange.send()
        write(value)
    }

    /// Pretty-printed, and slashes left alone — same reason as
    /// `snippets.json`: this file is meant to be opened, edited by hand, and
    /// handed to somebody else's Mac.
    private func write(_ file: File) {
        guard !fileBroken else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        do {
            try encoder.encode(file).write(to: Self.file, options: .atomic)
        } catch {
            NSLog("Sandy: cannot write config.json: \(error.localizedDescription)")
        }
    }

    static func reveal() {
        if !FileManager.default.fileExists(atPath: file.path) {
            shared.write(shared.value)
        }
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }
}

extension Notification.Name {
    static let sandyApplyProfile = Notification.Name("SandyApplyProfile")
}
