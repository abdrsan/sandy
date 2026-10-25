import AppKit
import SwiftUI

/// A brief glow under the notch when an agent finishes a response.
///
/// It lives in its own borderless window, not inside the panel's content:
/// the panel is a folded black strip most of the time, with no content view
/// at all, and the whole point of the glow is to be seen exactly then. The
/// window ignores the pointer and removes itself; nothing is left behind.
@MainActor
enum CelebrationGlow {
    private static let lifetime: TimeInterval = 2.4
    private static let size = NSSize(width: 220, height: 44)

    static func show() {
        for screen in NSScreen.screens {
            let frame = NSRect(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.maxY - size.height,
                width: size.width, height: size.height
            )
            let window = NSWindow(
                contentRect: frame, styleMask: [.borderless],
                backing: .buffered, defer: false
            )
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.level = .statusBar
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.contentView = NSHostingView(rootView: GlowView(lifetime: lifetime))
            window.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + lifetime + 0.2) {
                window.orderOut(nil)
                window.contentView = nil
            }
        }
    }
}

/// One soft bloom: fade in fast, breathe, fade out. Pure opacity math on a
/// radial gradient — no timing hooks, so the view dies with its window.
private struct GlowView: View {
    let lifetime: TimeInterval
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let p = min(1, max(0, context.date.timeIntervalSince(start) / lifetime))
            let alpha = sin(p * .pi)          // 0 → 1 → 0 over the lifetime
            Ellipse()
                .fill(RadialGradient(
                    colors: [Color.cyan.opacity(alpha), Color.clear],
                    center: .center, startRadius: 0, endRadius: 110
                ))
                .frame(width: 220, height: 44)
                .blur(radius: 8)
        }
    }
}
