import AppKit
import Combine
import SwiftUI

/// A small persistent indicator under the notch while a pomodoro runs —
/// same trick as CelebrationGlow (own borderless window, pointer-transparent),
/// but staying up for the whole cycle instead of flashing once.
@MainActor
final class PomodoroBadge {
    private var window: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func bind(to store: UtilitiesStore) {
        store.$pomodoroIsWork
            .removeDuplicates()
            .sink { [weak self] work in
                if work == nil { self?.hide() } else { self?.show(store) }
            }
            .store(in: &cancellables)
    }

    private func show(_ store: UtilitiesStore) {
        guard window == nil else { return }
        let size = NSSize(width: 132, height: 22)
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let window = NSWindow(
            contentRect: NSRect(x: screen.frame.midX - size.width / 2,
                                y: screen.frame.maxY - size.height - 2,
                                width: size.width, height: size.height),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView = NSHostingView(rootView: BadgeView(store: store))
        window.orderFrontRegardless()
        self.window = window
    }

    private func hide() {
        window?.orderOut(nil)
        window = nil
    }
}

/// Focus/break label plus the live countdown — straight from the store, no
/// timers of its own.
private struct BadgeView: View {
    @ObservedObject var store: UtilitiesStore

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(store.pomodoroIsWork == true ? Color.orange : Color.cyan)
                .frame(width: 5, height: 5)
            Text("\(localized(store.pomodoroIsWork == true ? "Focus" : "Break")) \(clock)")
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.9))
            if store.pomodoroRounds > 0 {
                Text("×\(store.pomodoroRounds)")
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 18)
        .background(Capsule().fill(Color.black.opacity(0.75)))
    }

    private var clock: String {
        let total = Int(store.remaining.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
