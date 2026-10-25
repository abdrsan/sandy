import SwiftUI

struct LanguageShortcutSettingsPane: View {
    @ObservedObject private var language = LanguageSettings.shared
    @ObservedObject private var shortcut = GlobalShortcut.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "globe").frame(width: 16).foregroundStyle(Theme.secondary)
                Text(localized("Language"))
                Spacer(minLength: 8)
                Picker(localized("Language"), selection: Binding(
                    get: { language.selection }, set: { language.select($0) }
                )) {
                    ForEach(InterfaceLanguage.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            Divider().overlay(Theme.hairline)
            HStack {
                Text(localized("Enable Keyboard Shortcut"))
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(
                    get: { shortcut.enabled }, set: { shortcut.setEnabled($0) }
                ))
                .toggleStyle(NotchToggleStyle())
                .labelsHidden()
                .accessibilityLabel(Text(localized("Enable Keyboard Shortcut")))
            }
            HStack {
                Text(localized("Keyboard Shortcut"))
                Spacer(minLength: 8)
                Picker(localized("Keyboard Shortcut"), selection: Binding(
                    get: { shortcut.shortcut }, set: { shortcut.select($0) }
                )) {
                    ForEach(PanelShortcut.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .disabled(!shortcut.enabled)
            }
            Text(localized(shortcut.registrationFailed
                ? "This shortcut is unavailable. Choose another combination."
                : "Press the shortcut again or Esc to close."))
                .font(.system(size: 10))
                .foregroundStyle(shortcut.registrationFailed ? Color.orange : Theme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(.white)
        .padding(8)
    }
}
