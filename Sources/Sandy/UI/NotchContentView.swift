import SwiftUI

struct NotchContentView: View {
    @ObservedObject var vm: NotchViewModel
    /// This screen's share of the panel. Everything the pointer decides is
    /// here; everything shown is in `vm`, the same on every display.
    @ObservedObject var panel: PanelState
    @ObservedObject private var language = LanguageSettings.shared
    @ObservedObject private var config = ConfigStore.shared

    private var isOpen: Bool { panel.isActive }
    private var size: CGSize { panel.bodySize }
    private var topRadius: CGFloat { isOpen ? Theme.openTopRadius : Theme.collapsedTopRadius }

    /// Whether the shape is painted at all.
    ///
    /// Folded over a real notch there is nothing to paint: the notch is a hole,
    /// and a hole is already black. The filled shape on top of it is invisible
    /// — but only for as long as what is behind it stays black, and that is not
    /// something the panel gets to assume. The window is `.stationary` and
    /// joins every space, so it stands still while the desktop moves: in
    /// Mission Control and mid-swipe between spaces the desktop shrinks away
    /// and the "notch" is left hanging in the air as a black rectangle over the
    /// Spaces bar. It reads as a second, squarer notch, which is exactly what
    /// it is — a picture of a hole with no hole behind it.
    ///
    /// A drawn notch is the opposite case: there the shape *is* the notch, and
    /// it has to be visible wherever the panel stands. So the rule is narrow —
    /// only the display that has a real cutout, and only while the panel has
    /// nothing of its own to show.
    ///
    /// "Nothing of its own" is asked of the body rather than of `isOpen`, and
    /// the difference is not stylistic. On a hole the body is the notch exactly
    /// when there is nothing to show — folded, `bodySize` is `collapsedSize`,
    /// and on a hole that is the notch itself —
    /// so any future state that grows the folded strip paints itself without
    /// anyone remembering to come back here. Keyed on `isOpen`, the next such
    /// state would draw its text onto a transparent background: white letters
    /// standing on the desktop with nothing behind them.
    private var paintsShape: Bool {
        !panel.geometry.isPhysical || size != panel.geometry.notchSize
    }

    var body: some View {
        // The shape is wider than the body by `topRadius` on each side: that
        // slack is where the concave shoulders live, so it must not be clipped.
        ZStack(alignment: .top) {
            NotchShape(
                topRadius: topRadius,
                bottomRadius: isOpen ? Theme.openBottomRadius : Theme.collapsedBottomRadius
            )
            .fill(paintsShape ? Color.black : Color.clear)
            .frame(width: size.width + 2 * topRadius, height: size.height)
            .shadow(color: .black.opacity(isOpen ? 0.5 : 0), radius: 18, y: 8)

            VStack(spacing: 0) {
                header
                if isOpen {
                    content
                        .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipped()
            .id(language.selection)
        }
        .frame(width: size.width + 2 * topRadius, height: size.height, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Theme.openAnimation, value: isOpen)
        .animation(Theme.paneAnimation, value: vm.tab)
        .transaction { if !config.animationsEnabled { $0.animation = nil } }
        .environment(\.locale, language.locale)
        .onChange(of: language.selection) { _, _ in vm.agents.refreshNotificationAuthorization() }
    }

    // MARK: - Header
    //
    // The strip shares a line with the tab switcher so the controls sit level
    // with the title. The tab switcher is only interactive in the open panel.

    private var header: some View {
        HStack(spacing: 0) {
            if isOpen {
                Text(vm.showFirstRunSetup ? localized("Welcome to Sandy").uppercased() : vm.tab.title.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.tertiary)
                    .padding(.leading, 16)
                    .id(vm.tab)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
            Color.clear.frame(width: panel.geometry.notchSize.width, height: 1)
            Spacer(minLength: 0)
            if isOpen {
                trailing
                    .padding(.trailing, 16)
                    .transition(.opacity)
            }
        }
        .frame(height: panel.geometry.notchSize.height)
    }

    @ViewBuilder
    private var trailing: some View {
        switch vm.tab {
        case .agents:
            counter(vm.agents.activeCount)
        case .media:
            HStack(spacing: 6) {
                if vm.media.track != nil {
                    EqualizerBars(isAnimating: vm.media.isPlaying)
                }
                Text(vm.media.sourceName ?? "")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.tertiary)
            }
        case .shelf:
            counter(vm.shelf.items.count)
        case .clipboard:
            counter(vm.clipboard.items.count)
        case .snippets:
            counter(vm.snippets.items.count)
        case .calendar:
            if let next = vm.calendar.next {
                Text(CalendarPane.countdown(to: next, from: vm.calendar.now))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(next.isRunning ? Color.white.opacity(0.8) : Theme.tertiary)
            }
        case .translate:
            // Nothing: the columns name both languages already, and the strip
            // is the one part of the panel worth not spending on a repeat.
            EmptyView()
        case .currency:
            CurrencyRateDate(currencies: vm.currencies)
        case .notes:
            NotesCounter(notes: vm.notes)
        case .teleprompter:
            EmptyView()
        case .utilities:
            EmptyView()
        case .settings:
            EmptyView()
        }
    }

    @ViewBuilder
    private func counter(_ value: Int) -> some View {
        if value > 0 {
            Text("\(value)")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.tertiary)
        }
    }

    // MARK: - Body

    @ViewBuilder
    private var content: some View {
        Group {
            if vm.showFirstRunSetup {
                FirstRunSetupPane(panel: panel)
            } else {
                VStack(spacing: 8) {
                    TabSwitcher(vm: vm, panel: panel, tabs: vm.visibleTabs)
                    panes
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, NotchGeometry.bodyBottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var panes: some View {
        // Content is replaced in place — no travel. The tabs sit above the
        // pane, so a direction would only be decoration.
        ZStack {
            pane
                .id(vm.tab)
                .transition(.asymmetric(
                    insertion: .opacity
                        .combined(with: .scale(scale: 0.97))
                        .animation(Theme.paneIn),
                    removal: .opacity
                        .combined(with: .scale(scale: 1.02))
                        .animation(Theme.paneOut)
                ))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    @ViewBuilder
    private var pane: some View {
        switch vm.tab {
        case .agents:
            AgentsPane(store: vm.agents, privacy: vm.privacy)
        case .media:
            MediaPane(media: vm.media)
        case .shelf:
            ShelfPane(shelf: vm.shelf, isTargeted: panel.isDropTargeted)
        case .clipboard:
            ClipboardPane(clipboard: vm.clipboard, privacy: vm.privacy)
        case .calendar:
            CalendarPane(calendar: vm.calendar, privacy: vm.privacy)
        case .snippets:
            SnippetsPane(snippets: vm.snippets, privacy: vm.privacy, wantsKeyboard: $panel.wantsKeyboard)
        case .translate:
            TranslatePane(translator: vm.translator, wantsKeyboard: $panel.wantsKeyboard)
        case .currency:
            CurrencyPane(currencies: vm.currencies, wantsKeyboard: $panel.wantsKeyboard)
        case .notes:
            NotesPane(notes: vm.notes, privacy: vm.privacy, wantsKeyboard: $panel.wantsKeyboard)
        case .teleprompter:
            TeleprompterPane(prompter: vm.teleprompter, wantsKeyboard: $panel.wantsKeyboard)
        case .utilities:
            UtilitiesPane(lock: vm.keyboardLock, utilities: vm.utilities)
        case .settings:
            SettingsPane(vm: vm, shelf: vm.shelf, screenshots: vm.screenshotFolder)
        }
    }
}

private struct FirstRunSetupPane: View {
    @ObservedObject var panel: PanelState
    @ObservedObject private var config = ConfigStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localized("Welcome to Sandy"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            Text(localized("Hover over the notch or press %@ to open Sandy.", config.panelShortcut.title))
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(localized("Use Settings to choose the tabs you want and enable monitoring for local Claude Code or Codex sessions. Permissions are requested only when a feature needs them."))
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 2)

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button(localized("Start Using Sandy")) {
                    panel.finishFirstRunSetup?(false)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondary)

                Button(localized("Set Up in Settings")) {
                    panel.finishFirstRunSetup?(true)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Capsule().fill(Theme.surfaceHover))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Watches the note store itself rather than reading through the view model:
/// notes are born and deleted inside the pane while this counter is on
/// screen, and the view model deliberately does not forward keystroke-driven
/// stores.
private struct NotesCounter: View {
    @ObservedObject var notes: NoteStore

    var body: some View {
        if !notes.notes.isEmpty {
            Text("\(notes.notes.count)")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.tertiary)
        }
    }
}

/// Same reason as `NotesCounter`: rate fetches must not redraw the whole panel
/// on every keystroke in the amount fields, so the date badge observes the
/// store on its own.
private struct CurrencyRateDate: View {
    @ObservedObject var currencies: CurrencyStore

    var body: some View {
        if let date = currencies.rateDate {
            Text(date)
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.tertiary)
        }
    }
}

/// Horizontal tab switcher along the top of the open panel.
///
/// Hovering switches tabs, but only after the pointer has stopped: a pointer
/// crossing the rail on its way somewhere else is gone in a few dozen
/// milliseconds, while one that came to choose stays put. The same dwell
/// threshold is what separates "the mouse was flung across the top of the
/// screen" from "the mouse came to the notch" in `PointerWatcher`.
private struct TabSwitcher: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var panel: PanelState
    /// Tabs currently enabled in Settings.
    let tabs: [NotchViewModel.Tab]

    @State private var hovered: NotchViewModel.Tab?

    /// Long enough to swallow a pass-through, short enough that a deliberate
    /// hover still feels like it answered instantly.
    private let dwell = Duration.milliseconds(150)

    var body: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            buttons
            Spacer(minLength: 0)
        }
        .frame(height: 28)
        .animation(Theme.contentAnimation, value: hovered)
        // Moving to another icon cancels the pending switch along with the
        // task, so only the icon actually rested on ever wins.
        .task(id: hovered) {
            guard let hovered, hovered != vm.tab else { return }
            try? await Task.sleep(for: dwell)
            guard !Task.isCancelled else { return }
            panel.select(hovered)
        }
    }

    @ViewBuilder
    private var buttons: some View {
        ForEach(tabs) { tab in
            Button {
                panel.select(tab)
            } label: {
                Image(systemName: tab.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 32, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(fill(for: tab))
                    )
                    .foregroundStyle(vm.tab == tab ? Color.white : Theme.tertiary)
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .scaleEffect(hovered == tab ? 1.15 : 1)
            }
            .buttonStyle(.plain)
            .help(tab.title)
            .accessibilityLabel(tab.title)
            .onHover { inside in
                if inside {
                    hovered = tab
                } else if hovered == tab {
                    hovered = nil
                }
            }
        }
    }

    private func fill(for tab: NotchViewModel.Tab) -> Color {
        if vm.tab == tab { return accentColor }
        return hovered == tab ? Theme.surface : .clear
    }

    private var accentColor: Color {
        switch ConfigStore.shared.accent {
        case "blue": .cyan
        case "purple": .purple
        case "orange": .orange
        default: .mint
        }
    }
}
