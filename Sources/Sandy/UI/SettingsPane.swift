import SwiftUI
import ServiceManagement
import Translation

/// What used to live in the status bar menu, minus the two items that belong
/// there: opening the panel and hiding its contents are both things people
/// reach for in a hurry, often without wanting to open the panel at all — the
/// rest is configuration, read rarely, and reads better as a tab like any
/// other than as a menu that grows a new row per feature.
struct SettingsPane: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var shelf: ShelfStore
    let screenshots: ScreenshotFolderWatcher
    @ObservedObject private var config = ConfigStore.shared

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var menuBarIconVisible = AppDelegate.isMenuBarIconVisible
    @State private var saveClipboardImages = NotchViewModel.saveClipboardImagesEnabled
    @State private var allDisplays = NotchGeometry.showsOnAllDisplays
    @State private var fullSizeNotch = NotchGeometry.drawsFullSizeNotch
    @State private var watchScreenshotFolder = false
    @State private var screenshotUsage: (files: Int, bytes: Int64) = (0, 0)
    @State private var translatePicking: String?
    @State private var translateLanguages: [Locale.Language] = []

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                section(localized("General")) {
                    LanguageShortcutSettingsPane()
                    toggleRow(
                        symbol: "arrow.forward.to.line",
                        title: localized("Launch at Login"),
                        isOn: launchAtLoginBinding
                    )
                    // Off means the same thing a ⌘-drag off the bar does —
                    // both go through `AppDelegate.isMenuBarIconVisible`, so
                    // whichever one somebody used, this switch shows it (#5).
                    toggleRow(
                        symbol: "eye.fill",
                        title: localized("Show Menu Bar Icon"),
                        isOn: menuBarIconVisibleBinding
                    )
                }

                // The rail is for what gets a glance between other things.
                // A tab used once a month is not banned from it, but it lives
                // there only as long as whoever never uses it can take it off —
                // and off means quiet too: its background stops with the icon.
                section(localized("Show in Panel")) {
                    ForEach(NotchViewModel.Tab.leftRail + NotchViewModel.Tab.rightRail) { tab in
                        if tab.canHide {
                            toggleRow(symbol: tab.symbol, title: tab.title, isOn: visibilityBinding(tab))
                        }
                    }
                }

                section(localized("Displays")) {
                    toggleRow(
                        symbol: "display.2",
                        title: localized("Show on All Displays"),
                        isOn: allDisplaysBinding
                    )
                    toggleRow(
                        symbol: "rectangle.topthird.inset.filled",
                        title: localized("Full-Height Notch Without a Cutout"),
                        isOn: fullSizeNotchBinding
                    )
                }

                section(localized("Screenshots")) {
                    toggleRow(
                        symbol: "photo.on.rectangle",
                        title: localized("Save Clipboard Screenshots"),
                        isOn: saveClipboardImagesBinding
                    )
                    toggleRow(
                        symbol: "eye",
                        title: localized("Watch Screenshots Folder"),
                        isOn: watchScreenshotFolderBinding
                    )
                    actionRow(symbol: "folder", title: localized("Show Screenshots Folder")) {
                        ScreenshotVault.reveal()
                    }
                    toggleRow(
                        symbol: "list.bullet",
                        title: localized("Remove Only Listed Files"),
                        isOn: Binding(
                            get: { config.clearOnlyShelfFiles },
                            set: { config.clearOnlyShelfFiles = $0 }
                        )
                    )
                    actionRow(
                        symbol: "trash",
                        title: clearTitle,
                        disabled: screenshotUsage.files == 0
                    ) {
                        if config.clearOnlyShelfFiles {
                            shelf.clearVaultFiles()
                        } else {
                            ScreenshotVault.clear()
                            shelf.load()
                            shelf.refreshFromDisk()
                        }
                        refreshUsage()
                    }
                }

                section(localized("Clipboard")) {
                    toggleRow(
                        symbol: "clock.arrow.circlepath",
                        title: localized("Keep History Between Launches"),
                        isOn: Binding(get: { config.clipboardPersist }, set: { config.clipboardPersist = $0 })
                    )
                    optionRow(
                        symbol: "number", title: localized("History Size"),
                        options: [40, 200, 500], current: config.clipboardLimit
                    ) { config.clipboardLimit = $0 }
                    if !config.clipboardExcludedApps.isEmpty {
                        actionRow(
                            symbol: "app.badge.checkmark",
                            title: "\(localized("Excluded Apps")) (\(config.clipboardExcludedApps.count)) — \(localized("Clear"))"
                        ) { config.clipboardExcludedApps = [] }
                    }
                }

                section(localized("Calendar")) {
                    toggleRow(
                        symbol: "bell",
                        title: localized("Meeting Reminders"),
                        isOn: meetingAlertsBinding
                    )
                    if config.meetingAlerts {
                        optionRow(
                            symbol: "clock", title: localized("Before Start"),
                            options: [1, 5, 10], current: config.meetingAlertMinutes
                        ) {
                            config.meetingAlertMinutes = $0
                            vm.calendar.refreshAlerts()
                        }
                    }
                }

                section(localized("Translate")) {
                    languageRow(
                        title: localized("Translate From"), key: "from", code: config.translateSource
                    )
                    if translatePicking == "from" {
                        languageList { config.translateSource = $0 }
                    }
                    languageRow(
                        title: localized("Translate To"), key: "to", code: config.translateTarget
                    )
                    if translatePicking == "to" {
                        languageList { config.translateTarget = $0 }
                    }
                    actionRow(symbol: "globe", title: localized("Translation Languages…")) {
                        Translator.openLanguageSettings()
                    }
                }

                section(localized("Snippets")) {
                    actionRow(symbol: "doc.text", title: localized("Show Snippets File")) {
                        vm.snippets.reveal()
                    }
                }

                // What lives in this file is documented in #67: everything
                // above that makes sense on another Mac, in one place instead
                // of five.
                section(localized("Configuration")) {
                    if config.fileBroken { configBrokenNotice }
                    actionRow(symbol: "gearshape", title: localized("Show Config File")) {
                        ConfigStore.reveal()
                    }
                }

                AgentSettingsPane(store: vm.agents)
                MobileSettingsPane(agents: vm.agents)

                // The one door left once the menu bar icon is gone (#5): a
                // status item is not required to hide it any more, so quitting
                // must not require one either. Last on purpose — leaving is
                // not something to meet on the way to a switch.
                section(localized("Sandy")) {
                    actionRow(symbol: "power", title: localized("Quit Sandy")) {
                        NSApp.terminate(nil)
                    }
                }
            }
            .padding(.top, 2)
            .padding(.trailing, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Live state, not a snapshot taken once at launch: System Settings can
        // flip Launch at Login from outside, and the folder can empty or fill
        // between visits to this tab (#11 taught the same lesson for the menu
        // this replaces).
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            // Also flipped by a ⌘-drag off the bar, not only by the switch
            // below it — re-read for the same reason as the rest of this block.
            menuBarIconVisible = AppDelegate.isMenuBarIconVisible
            saveClipboardImages = NotchViewModel.saveClipboardImagesEnabled
            allDisplays = NotchGeometry.showsOnAllDisplays
            fullSizeNotch = NotchGeometry.drawsFullSizeNotch
            watchScreenshotFolder = screenshots.isEnabled
            refreshUsage()
        }
        .task {
            // `LanguageAvailability` is not Sendable, so it is created and
            // asked inside a detached task rather than crossing the actor.
            // The list is what macOS can translate between; whether a pack is
            // installed is decided later, at translate time.
            let languages = await Task.detached {
                await LanguageAvailability().supportedLanguages
            }.value
            translateLanguages = languages
                .sorted { Self.languageName($0) < Self.languageName($1) }
        }
    }

    private var meetingAlertsBinding: Binding<Bool> {
        Binding(
            get: { config.meetingAlerts },
            set: { wants in
                if wants {
                    // The switch is the explicit ask — the system prompt comes
                    // from this press and nowhere else.
                    Task {
                        let granted = await vm.calendar.requestAlertPermission()
                        ConfigStore.shared.meetingAlerts = granted
                        vm.calendar.refreshAlerts()
                    }
                } else {
                    ConfigStore.shared.meetingAlerts = false
                    vm.calendar.refreshAlerts()
                }
            }
        )
    }

    private func languageRow(title: String, key: String, code: String) -> some View {
        Button {
            translatePicking = translatePicking == key ? nil : key
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "character.bubble")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Text(code.isEmpty ? localized("Automatic") : Self.languageName(Locale.Language(identifier: code)))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.tertiary)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func languageList(_ select: @escaping (String) -> Void) -> some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 1) {
                languageOption(code: "", name: localized("Automatic"), select: select)
                ForEach(translateLanguages, id: \.minimalIdentifier) { language in
                    languageOption(code: language.minimalIdentifier, name: Self.languageName(language), select: select)
                }
            }
        }
        .frame(maxHeight: 110)
    }

    private func languageOption(code: String, name: String, select: @escaping (String) -> Void) -> some View {
        Button {
            select(code)
            translatePicking = nil
            // A stale result in the old pair must not sit under the new labels.
            vm.translator.retry()
        } label: {
            Text(name)
                .font(.system(size: 11))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static func languageName(_ language: Locale.Language) -> String {
        let code = language.languageCode?.identifier ?? language.minimalIdentifier
        let name = Locale(identifier: appLanguage).localizedString(forLanguageCode: code) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// A row of capsule options — for settings that take one of a few values.
    private func optionRow(
        symbol: String, title: String, options: [Int], current: Int, set: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            ForEach(options, id: \.self) { option in
                Button { set(option) } label: {
                    Text("\(option)")
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(option == current ? .white : Theme.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(option == current ? Theme.surfaceHover : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
    }

    private var clearTitle: String {
        guard screenshotUsage.files > 0 else { return localized("Clear Screenshots Folder") }
        let size = ByteCountFormatter.string(fromByteCount: screenshotUsage.bytes, countStyle: .file)
        return localized("Clear Screenshots Folder (%@)", size)
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { wants in
                do {
                    if wants {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    NSLog("Sandy: launch-at-login failed: \(error.localizedDescription)")
                }
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        )
    }

    private var menuBarIconVisibleBinding: Binding<Bool> {
        Binding(
            get: { menuBarIconVisible },
            set: { wants in
                menuBarIconVisible = wants
                AppDelegate.isMenuBarIconVisible = wants
            }
        )
    }

    private func visibilityBinding(_ tab: NotchViewModel.Tab) -> Binding<Bool> {
        Binding(
            get: { vm.isVisible(tab) },
            set: { wants in vm.setVisible(tab, wants) }
        )
    }

    private var saveClipboardImagesBinding: Binding<Bool> {
        Binding(
            get: { saveClipboardImages },
            set: { wants in
                saveClipboardImages = wants
                NotchViewModel.saveClipboardImagesEnabled = wants
            }
        )
    }

    /// Turning this off folds the panel back to one screen — the notched one
    /// if this Mac has a notch, the main display otherwise. The panels are
    /// rebuilt on the spot, so the switch is its own confirmation.
    private var allDisplaysBinding: Binding<Bool> {
        Binding(
            get: { allDisplays },
            set: { wants in
                allDisplays = wants
                NotchGeometry.showsOnAllDisplays = wants
            }
        )
    }

    /// Where a display has no cutout, the notch is drawn as a thin strip along
    /// the top edge; this brings back the old one, the height of the menu bar.
    /// Panels rebuild on the spot, so the switch is its own confirmation.
    private var fullSizeNotchBinding: Binding<Bool> {
        Binding(
            get: { fullSizeNotch },
            set: { wants in
                fullSizeNotch = wants
                NotchGeometry.drawsFullSizeNotch = wants
            }
        )
    }

    /// Turning off is instant. Turning on goes through the Open panel first —
    /// `requestAccess` is itself the consent, so the switch only follows what
    /// actually happened once the panel closes, not the click that opened it.
    private var watchScreenshotFolderBinding: Binding<Bool> {
        Binding(
            get: { watchScreenshotFolder },
            set: { wants in
                if wants {
                    screenshots.requestAccess { granted in watchScreenshotFolder = granted }
                } else {
                    screenshots.disable()
                    watchScreenshotFolder = false
                }
            }
        )
    }

    /// Off the main thread: walking the folder takes as long as the folder is
    /// big, and this is the thread the whole panel lives on (#11).
    private func refreshUsage() {
        DispatchQueue.global(qos: .userInitiated).async {
            let usage = ScreenshotVault.usage()
            DispatchQueue.main.async { screenshotUsage = usage }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func section<Rows: View>(_ title: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.tertiary)
                .padding(.leading, 8)
            VStack(spacing: 1) {
                rows()
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.surface)
            )
        }
    }

    private func toggleRow(symbol: String, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .toggleStyle(NotchToggleStyle())
                .labelsHidden()
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
    }

    /// The refusal to write over a broken file (#7) is only honest if it is
    /// said out loud — same reasoning as `SnippetsPane.brokenNotice`.
    private var configBrokenNotice: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.yellow.opacity(0.85))
            Text(localized("config.json is broken — click to open; nothing is overwritten"))
                .font(.system(size: 10))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { ConfigStore.reveal() }
        .padding(.horizontal, 8)
        .frame(height: 26)
    }

    private func actionRow(
        symbol: String,
        title: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }
}
