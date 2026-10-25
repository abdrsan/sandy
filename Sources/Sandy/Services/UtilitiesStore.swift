import AppKit
import UserNotifications

/// The two small switches that share the Utilities tab with the keyboard
/// lock: a glance timer and a "keep the Mac awake" toggle.
///
/// The timer keeps running while the panel is folded — the store lives in the
/// view model, not the pane — and reports the end with a system notification,
/// so it still lands when nobody is looking at the notch. Permission is asked
/// on the first Start press, which is the explicit user action that makes the
/// notification make sense.
@MainActor
final class UtilitiesStore: ObservableObject {
    /// Seconds left, for the countdown label. 0 when nothing is running.
    @Published private(set) var remaining: TimeInterval = 0
    /// Whether `caffeinate` is holding sleep off right now.
    @Published private(set) var keepAwake = false

    static let presetMinutes = [5, 10, 25]

    private var timer: Timer?
    private var endsAt: Date?
    private var caffeine: Process?

    var timerRunning: Bool { endsAt != nil }

    // MARK: - Timer

    func startTimer(minutes: Int) {
        guard minutes > 0 else { return }
        cancelTimer()
        endsAt = Date().addingTimeInterval(TimeInterval(minutes) * 60)
        remaining = TimeInterval(minutes) * 60
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // Idempotent after the first grant; the dialog appears only once.
        Task { await Self.requestNotificationPermission() }
    }

    func cancelTimer() {
        timer?.invalidate()
        timer = nil
        endsAt = nil
        remaining = 0
    }

    private func tick() {
        guard let endsAt else { return }
        let left = endsAt.timeIntervalSinceNow
        guard left > 0 else {
            cancelTimer()
            Self.postTimerDone()
            return
        }
        remaining = left
    }

    // MARK: - Keep awake

    /// `caffeinate -di` holds display and system sleep for as long as the
    /// process lives — cheaper and more honest than IOPMAssertion bookkeeping,
    /// because the exit *is* the release, including the crash case.
    func setKeepAwake(_ on: Bool) {
        if on {
            guard caffeine?.isRunning != true else { keepAwake = true; return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
            process.arguments = ["-di"]
            do {
                try process.run()
                caffeine = process
                keepAwake = true
            } catch {
                NSLog("Sandy: caffeinate failed to launch: \(error.localizedDescription)")
            }
        } else {
            caffeine?.terminate()
            caffeine = nil
            keepAwake = false
        }
    }

    func stop() {
        cancelTimer()
        setKeepAwake(false)
    }

    // MARK: - Notification

    /// Same guard as AgentNotifications: UserNotifications wants a real app
    /// bundle, and tests must never reach for one.
    private static var center: UNUserNotificationCenter? {
        Bundle.main.bundleURL.pathExtension == "app" ? .current() : nil
    }

    private static func requestNotificationPermission() async {
        _ = try? await center?.requestAuthorization(options: [.alert, .sound])
    }

    private static func postTimerDone() {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = localized("Timer")
        content.body = localized("Time is up")
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "sandy.timer.\(UUID().uuidString)", content: content, trigger: nil
        )
        center.add(request) { _ in }
    }
}
