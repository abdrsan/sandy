import AppKit
import SwiftUI

struct ClipboardPane: View {
    @ObservedObject var clipboard: ClipboardStore
    @ObservedObject var privacy: PrivacyMode
    @State private var query = ""

    private var visible: [ClipItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return clipboard.items }
        return clipboard.items.filter { $0.preview.localizedCaseInsensitiveContains(needle) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if clipboard.items.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "list.clipboard")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(Theme.tertiary)
                    Text(localized("Nothing Copied Yet"))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TextField(localized("Search"), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 3) {
                        ForEach(visible) { item in
                            ClipRow(item: item, clipboard: clipboard, privacy: privacy)
                        }
                    }
                    .padding(.vertical, 4)
                }
                footer
            }
        }
        .padding(.top, 2)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let app = NSWorkspace.shared.frontmostApplication,
               let id = app.bundleIdentifier,
               id != Bundle.main.bundleIdentifier,
               !ConfigStore.shared.clipboardExcludedApps.contains(id) {
                Button {
                    var list = ConfigStore.shared.clipboardExcludedApps
                    if !list.contains(id) { list.append(id) }
                    ConfigStore.shared.clipboardExcludedApps = list
                } label: {
                    Image(systemName: "app.badge.checkmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                }
                .buttonStyle(.plain)
                .help(localized("Don't Save Copies from %@", app.localizedName ?? id))
            }
            Spacer()
            PrivacySwitch(privacy: privacy, section: .clipboard)
            Button("Clear") { clipboard.clear() }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.secondary)
        }
        .padding(.top, 2)
    }
}

private struct ClipRow: View {
    let item: ClipItem
    @ObservedObject var clipboard: ClipboardStore
    @ObservedObject var privacy: PrivacyMode
    @State private var hovering = false
    @State private var justCopied = false

    private var hidden: Bool { privacy.hides(.clipboard, item.id.uuidString) }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: justCopied ? "checkmark" : item.symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(justCopied ? Color.green : Theme.tertiary)
                .frame(width: 14)
            SpoilerText(
                text: item.preview.replacingOccurrences(of: "\n", with: " "),
                hidden: hidden,
                seed: UInt64(bitPattern: Int64(item.id.uuidString.hashValue))
            )
            Spacer(minLength: 6)
            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.secondary)
            }
            if hovering {
                if privacy.covers(.clipboard) {
                    RevealEye(hidden: hidden) { privacy.toggle(item.id.uuidString) }
                }
                Button { clipboard.togglePin(item) } label: {
                    Image(systemName: item.pinned ? "pin.slash" : "pin")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                }
                .buttonStyle(.plain)
                Button { clipboard.remove(item) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        // A file that is gone stays in the list, just faded — hiding it would
        // look like Sandy lost the entry.
        .opacity(item.fileMissing ? 0.45 : 1)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(hovering ? Theme.surfaceHover : Theme.surface)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            clipboard.copy(item)
            flash($justCopied)
        }
        .animation(Theme.contentAnimation, value: hovering)
        .animation(Theme.contentAnimation, value: justCopied)
    }
}
