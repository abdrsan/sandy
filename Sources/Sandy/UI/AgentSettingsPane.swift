import SwiftUI

/// Embedded in SettingsPane's existing scroll view. Every permission request
/// and hook change starts with one of the explicit controls in this section.
struct AgentSettingsPane: View {
    @ObservedObject var store: AgentMonitorStore
    @ObservedObject private var config = ConfigStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localized("Agent Monitoring").uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(Theme.tertiary)
                .padding(.leading, 8)
            VStack(alignment: .leading, spacing: 0) {
                toggle("Monitoring", symbol: "waveform.path.ecg", value: store.preferences.monitoringEnabled) { store.setMonitoring($0) }
                toggle("Claude Code", symbol: "terminal", value: store.preferences.claudeEnabled) { store.setSource(.claude, enabled: $0) }
                toggle("Codex", symbol: "chevron.left.forwardslash.chevron.right", value: store.preferences.codexEnabled) { store.setSource(.codex, enabled: $0) }
                Text(store.connectionMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.top, 3)
                    .padding(.bottom, 8)
                Divider().overlay(Theme.hairline).padding(.horizontal, 8)
                toggle("Agent Notifications", symbol: "bell", value: store.preferences.notificationsEnabled) { store.setNotifications($0) }
                    .help(localized("Sandy asks for notification permission only when you enable this switch."))
                toggle("Completion Glow", symbol: "sparkles", value: config.agentGlow) { config.agentGlow = $0 }
                    .help(localized("The notch lights up briefly when an agent finishes a response."))
                Text(store.notificationStatus)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                Divider().overlay(Theme.hairline).padding(.horizontal, 8)
                action("Install Claude Hooks", symbol: "plus.circle") { store.installClaudeHooks() }
                action("Remove Claude Hooks", symbol: "minus.circle") { store.uninstallClaudeHooks() }
                Text(localized("Claude hooks are installed only when you click Install. Your existing hooks are kept."))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                if store.commandInProgress {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.mini)
                        Text(localized("Updating Claude Hooks…"))
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                } else if let message = store.commandMessage {
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                }
            }
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
        }
        .onAppear { store.refreshNotificationAuthorization() }
    }

    private func toggle(_ key: String, symbol: String, value: Bool, action: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .frame(width: 16)
            Text(localized(key))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(get: { value }, set: { action($0) }))
                .toggleStyle(NotchToggleStyle())
                .labelsHidden()
                .accessibilityLabel(Text(localized(key)))
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
    }

    private func action(_ key: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 16)
                Text(localized(key))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.commandInProgress || store.connection == .missingHelper)
        .opacity(store.commandInProgress || store.connection == .missingHelper ? 0.4 : 1)
    }
}
