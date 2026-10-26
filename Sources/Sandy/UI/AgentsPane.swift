import AppKit
import SwiftUI
import SandyMobileCore

/// The monitor owns all state and history; the pane only advances the visible
/// duration labels. Closing Sandy's panel tears this timeline down as well.
struct AgentsPane: View {
    @ObservedObject var store: AgentMonitorStore
    @ObservedObject var privacy: PrivacyMode
    @State private var showingAnalytics = false
    @State private var sourceFilter: AgentSource?
    @State private var stateFilter: AgentSessionState?
    @State private var pinnedSessionIDs = Set(UserDefaults.standard.stringArray(forKey: "pinnedAgentSessionIDs") ?? [])
    @State private var reviewRequest: MobileApproval?
    @ObservedObject private var mobile = MobileLinkStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            connectionStatus
            if !showingAnalytics { sourcePicker }
            if let message = store.historyErrorMessage {
                notice(message, symbol: "exclamationmark.triangle.fill", color: .yellow)
                HStack(spacing: 12) {
                    Button(localized("Show History File")) { store.showHistoryFile() }
                    Button(localized("Retry")) { store.retry() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.secondary)
            }
            if showingAnalytics {
                analytics
            } else {
                sessions
            }
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: store.navigationRequest) { _, _ in
            if store.selectedSessionID != nil { showingAnalytics = false }
        }
        .popover(item: $reviewRequest) { request in
            VStack(alignment:.leading,spacing:12) {
                Text(request.source+" · "+request.tool).font(.headline)
                ScrollView { Text(request.context).font(.system(size:11,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }
                HStack {
                    Button(localized("Deny")) { mobile.decideLocally(request,action:"deny"); reviewRequest=nil }
                    Spacer()
                    Button(localized("Allow Once")) { mobile.decideLocally(request,action:"allow"); reviewRequest=nil }
                }
            }.padding(16).frame(width:430,height:280)
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            modeButton("Sessions", analytics: false)
            modeButton("Analytics", analytics: true)
            Spacer(minLength: 6)
            Text(localized("Active: %d", store.activeCount))
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.secondary)
            PrivacySwitch(privacy: privacy, section: .agents)
            Button { store.showSettings() } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(localized("Agent Monitoring"))
        }
    }

    private func modeButton(_ key: String, analytics: Bool) -> some View {
        Button { showingAnalytics = analytics } label: {
            Text(localized(key))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(showingAnalytics == analytics ? .white : Theme.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(showingAnalytics == analytics ? Theme.surfaceHover : .clear))
        }
        .buttonStyle(.plain)
    }

    private var connectionStatus: some View {
        HStack(alignment: .center, spacing: 7) {
            Circle()
                .fill(connectionColor)
                .frame(width: 5, height: 5)
            Text(store.connectionMessage)
                .font(.system(size: 10))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if store.preferences.monitoringEnabled,
               store.connection == .failed || store.connection == .missingHelper {
                Button(localized("Retry")) { store.retry() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
    }

    private var connectionColor: Color {
        switch store.connection {
        case .running: .green.opacity(0.85)
        case .starting: .yellow.opacity(0.85)
        case .failed, .missingHelper: .orange
        case .stopped, .sleeping: Theme.tertiary
        }
    }

    private var sessions: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                if store.sessions.isEmpty {
                    emptyState
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        LazyVStack(spacing: 7) {
                            ForEach(mobile.approvalRequests) { request in approvalCard(request) }
                            ForEach(AgentSource.allCases.filter { sourceFilter == nil || $0 == sourceFilter }) { source in
                                let group = store.sessions.filter { $0.source == source && (stateFilter == nil || $0.state == stateFilter) }
                                    .sorted { pinnedSessionIDs.contains($0.id) && !pinnedSessionIDs.contains($1.id) }
                                if !group.isEmpty {
                                    HStack(spacing:6) {
                                        Image(systemName:source == .claude ? "sun.max.fill":"sparkle").foregroundStyle(source == .claude ? Color.orange:Color.indigo)
                                        Text("\(source.title) (\(group.count))").foregroundStyle(Theme.secondary)
                                        Spacer()
                                    }.font(.system(size:10,weight:.semibold,design:.monospaced)).padding(.top,5)
                                    ForEach(group) { session in sessionRow(session,now:timeline.date).id(session.id) }
                                }
                            }
                        }
                        .padding(.bottom, 3)
                    }
                }
            }
            .onAppear { scroll(to: store.selectedSessionID, with: proxy) }
            .onChange(of: store.navigationRequest) { _, _ in scroll(to: store.selectedSessionID, with: proxy) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func scroll(to id: String?, with proxy: ScrollViewProxy) {
        guard let id else { return }
        withAnimation(Theme.contentAnimation) { proxy.scrollTo(id, anchor: .center) }
    }

    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing:5) {
                Button(localized("All")) { sourceFilter=nil }
                    .foregroundStyle(sourceFilter == nil ? Color.green:Theme.secondary)
                ForEach(AgentSource.allCases) { source in
                    Button(source.title) { sourceFilter=source }
                        .foregroundStyle(sourceFilter == source ? Color.green:Theme.secondary)
                }
                Spacer()
            }
            HStack(spacing:5) {
                ForEach(AgentSessionState.allCases, id: \.self) { state in
                    Button(localized(state.rawValue.capitalized)) { stateFilter = stateFilter == state ? nil : state }
                        .foregroundStyle(stateFilter == state ? state.displayColor : Theme.tertiary)
                }
                Spacer()
            }
        }.buttonStyle(.plain).font(.system(size:9,weight:.semibold,design:.monospaced))
    }

    private func approvalCard(_ request: MobileApproval) -> some View {
        VStack(alignment:.leading,spacing:8) {
            HStack {
                Image(systemName:"exclamationmark.circle.fill").foregroundStyle(.yellow)
                Text(request.source+" · "+request.tool).fontWeight(.semibold)
                Spacer()
                Button(localized("Deny")) { mobile.decideLocally(request,action:"deny") }
                Button(localized("Allow Once")) { reviewRequest=request }.foregroundStyle(.green)
            }
            SpoilerText(text:request.context,hidden:privacy.covers(.agents),font:.system(size:10,design:.monospaced),height:26,seed:seed(request.id))
        }.buttonStyle(.plain).font(.system(size:10)).padding(11)
          .background(RoundedRectangle(cornerRadius:13).fill(Color.yellow.opacity(0.08)))
          .overlay(RoundedRectangle(cornerRadius:13).stroke(Color.yellow.opacity(0.25),lineWidth:1))
    }

    private func sessionRow(_ session: AgentSession, now: Date) -> some View {
        let hidden=privacy.hides(.agents,session.id)
        let selected=store.selectedSessionID == session.id
        return HStack(alignment:.center,spacing:12) {
            AgentPixelAvatar(state:session.state,source:session.source)
            VStack(alignment:.leading,spacing:7) {
                HStack(spacing:5) {
                    SpoilerText(text:projectName(session.projectPath),hidden:hidden,
                        font:.system(size:13,weight:.bold,design:.monospaced),color:session.state == .working ? .green:.white,
                        height:16,seed:seed(session.id))
                    Spacer(minLength:0)
                    Button {
                        if pinnedSessionIDs.contains(session.id) { pinnedSessionIDs.remove(session.id) }
                        else { pinnedSessionIDs.insert(session.id) }
                        UserDefaults.standard.set(Array(pinnedSessionIDs), forKey: "pinnedAgentSessionIDs")
                    } label: {
                        Image(systemName: pinnedSessionIDs.contains(session.id) ? "pin.fill" : "pin")
                            .foregroundStyle(pinnedSessionIDs.contains(session.id) ? Color.yellow : Theme.tertiary)
                    }.buttonStyle(.plain).help(localized("Pinned"))
                    Text(formatTime(store.activeDuration(for:session,at:now)))
                        .font(.system(size:9,weight:.medium,design:.monospaced)).foregroundStyle(Theme.secondary)
                        .padding(.horizontal,6).padding(.vertical,3).background(RoundedRectangle(cornerRadius:5).fill(Color.white.opacity(0.06)))
                    if privacy.covers(.agents) { RevealEye(hidden:hidden) { privacy.toggle(session.id) } }
                    if !hidden,let path=session.projectPath,(path as NSString).isAbsolutePath {
                        Button { Self.openInTerminal(path) } label: { Image(systemName:"terminal").foregroundStyle(.green) }.help(localized("Open in Terminal"))
                        if let editor = Self.installedEditor {
                            Button { Self.openInApp(path, name: editor) } label: { Image(systemName:"chevron.left.forwardslash.chevron.right").font(.system(size:9,weight:.semibold)).foregroundStyle(Theme.tertiary) }.help("\(localized("Open in Editor")) — \(editor)")
                        }
                        Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath:path)]) } label: { Image(systemName:"folder").foregroundStyle(Theme.tertiary) }.help(localized("Show in Finder"))
                    }
                }
                HStack(spacing:6) {
                    Text("> ").foregroundStyle(session.state.displayColor).fontWeight(.bold)
                    SpoilerText(text:session.operation.map(localizedAgentOperation) ?? session.state.displayTitle,
                        hidden:hidden,font:.system(size:10,design:.monospaced),color:Theme.secondary,height:13,seed:seed(session.id)&+1)
                }
                HStack(spacing:8) {
                    Circle().fill(session.state.displayColor).frame(width:4,height:4)
                    Text(session.state.displayTitle).foregroundStyle(session.state.displayColor)
                    Spacer()
                    metric("Operations",value:number(session.operations),symbol:"wrench.and.screwdriver")
                }.font(.system(size:9,design:.monospaced))
            }
        }.buttonStyle(.plain).padding(12)
          .background(RoundedRectangle(cornerRadius:14).fill(selected ? Theme.surfaceHover:Color.white.opacity(0.035)))
          .overlay(RoundedRectangle(cornerRadius:14).stroke(selected ? Color.green.opacity(0.5):Color.white.opacity(0.045),lineWidth:1))
    }

    private var analytics: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(localized("Sessions: %d", store.sessions.count))
                    Spacer()
                    Text(localized("Saved on this Mac"))
                }
                .font(.system(size: 10))
                .foregroundStyle(Theme.secondary)
                .padding(.horizontal, 2)
                if store.summaries.isEmpty {
                    emptyState
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        VStack(spacing: 8) {
                            ForEach(store.summaries) { summary in summaryRow(summary) }
                        }
                    }
                    Text(localized("Token counts are cumulative. Missing values are shown as No Data."))
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func summaryRow(_ summary: AgentSummary) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text(summary.source.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                SpoilerText(
                    text: projectName(summary.projectPath), hidden: privacy.covers(.agents),
                    font: .system(size: 11, weight: .semibold), height: 13,
                    seed: seed(summary.id)
                )
            }
            HStack(spacing: 14) {
                metric("Sessions", value: number(summary.sessionCount), symbol: "rectangle.stack")
                metric("Active Time", value: formatTime(summary.activeSeconds), symbol: "timer")
                metric("Operations", value: number(summary.operations), symbol: "wrench.and.screwdriver")
                Spacer(minLength: 0)
            }
            tokenMetric(input: summary.inputTokens, output: summary.outputTokens)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
    }

    private func metric(_ key: String, value: String, symbol: String) -> some View {
        Label(value, systemImage: symbol)
            .font(.system(size: 9).monospacedDigit())
            .foregroundStyle(Theme.secondary)
            .help(localized(key))
            .accessibilityLabel(Text("\(localized(key)): \(value)"))
    }

    private func tokenMetric(input: Int?, output: Int?) -> some View {
        Text(localized("Tokens · in %@ · out %@", input.map(number) ?? localized("No Data"), output.map(number) ?? localized("No Data")))
            .font(.system(size: 9).monospacedDigit())
            .foregroundStyle(Theme.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Theme.tertiary)
            Text(localized("No Agent Sessions Yet"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            Text(localized(store.preferences.monitoringEnabled ? "Start a supported Claude Code or Codex session. Events will appear here." : "Enable monitoring in Settings to see your agent sessions here."))
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(localized("Agent Monitoring")) { store.showSettings() }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Theme.surfaceHover))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 18)
    }

    private func notice(_ message: String, symbol: String, color: Color) -> some View {
        Label(message, systemImage: symbol)
            .font(.system(size: 10))
            .foregroundStyle(color.opacity(0.9))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// `/usr/bin/open -a Terminal` rather than NSWorkspace's app-opening API:
    /// the session's project is untrusted input, and a spawned open(1) treats
    /// it as a path, never as something to interpret.
    private static func openInTerminal(_ path: String) {
        openInApp(path, name: "Terminal")
    }

    /// First matching code editor in /Applications — VS Code, then Cursor.
    /// Which editor a session actually runs in cannot be known from hooks;
    /// this just opens the project in whatever editor the user has.
    private static var installedEditor: String? {
        ["Visual Studio Code", "Cursor"].first {
            FileManager.default.fileExists(atPath: "/Applications/\($0).app")
        }
    }

    private static func openInApp(_ path: String, name: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", name, path]
        try? task.run()
    }

    private func projectName(_ path: String?) -> String {
        guard let path, !path.isEmpty else { return localized("Unknown Project") }
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? path : name
    }

    private func number(_ value: Int) -> String { value.formatted(.number.locale(Locale(identifier: appLanguage))) }
    private func seed(_ value: String) -> UInt64 { UInt64(bitPattern: Int64(value.hashValue)) }
}

extension AgentSessionState {
    var displayTitle: String {
        switch self {
        case .idle: localized("Idle")
        case .working: localized("Working")
        case .waiting: localized("Waiting for Input")
        case .ready: localized("Answer Ready")
        case .ended: localized("Session Ended")
        case .failed: localized("Agent Error")
        case .disconnected: localized("Disconnected")
        }
    }

    var displayColor: Color {
        switch self {
        case .working: .green.opacity(0.9)
        case .waiting: .yellow.opacity(0.9)
        case .ready: .cyan.opacity(0.9)
        case .failed: .orange
        case .idle, .ended, .disconnected: Theme.secondary
        }
    }
}
