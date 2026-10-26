import AppKit
import UserNotifications

/// The small switches that share the Utilities tab with the keyboard lock:
/// a glance timer, a pomodoro cycle, a water reminder and a "keep the Mac
/// awake" toggle.
///
/// Everything keeps running while the panel is folded — the store lives in
/// the view model, not the pane — and reports through system notifications,
/// so a finished pomodoro still lands when nobody is looking at the notch.
/// Permission is asked on the first explicit press of each feature.
@MainActor
final class UtilitiesStore: ObservableObject {
    /// Seconds left on the countdown label. 0 when nothing is running.
    @Published private(set) var remaining: TimeInterval = 0
    /// Whether `caffeinate` is holding sleep off right now.
    @Published private(set) var keepAwake = false
    /// Pomodoro: nil when off, otherwise the current phase.
    @Published private(set) var pomodoroIsWork: Bool?
    /// Completed focus blocks in the current pomodoro run.
    @Published private(set) var pomodoroRounds = 0
    /// Whether the water reminder is scheduled.
    @Published private(set) var waterOn = false
    /// Water reminder interval, minutes.
    @Published private(set) var waterMinutes = 45

    static let presetMinutes = [5, 10, 25]
    static let waterOptions = [30, 45, 60]
    static let workMinutes = 25
    static let breakMinutes = 5

    private var timer: Timer?
    private var waterTimer: Timer?
    private var endsAt: Date?
    private var caffeine: Process?
    private var pomodoro = false

    var timerRunning: Bool { endsAt != nil }
    var pomodoroRunning: Bool { pomodoro }

    // MARK: - Countdown

    func startTimer(minutes: Int) {
        guard minutes > 0 else { return }
        pomodoro = false
        startClock(seconds: TimeInterval(minutes) * 60)
        Task { await Self.requestNotificationPermission() }
    }

    func cancelTimer() {
        pomodoro = false
        pomodoroIsWork = nil
        timer?.invalidate()
        timer = nil
        endsAt = nil
        remaining = 0
    }

    private func startClock(seconds: TimeInterval) {
        timer?.invalidate()
        endsAt = Date().addingTimeInterval(seconds)
        remaining = seconds
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard let endsAt else { return }
        let left = endsAt.timeIntervalSinceNow
        guard left > 0 else {
            if pomodoro { advancePomodoro() } else { finishTimer() }
            return
        }
        remaining = left
    }

    private func finishTimer() {
        cancelTimer()
        Self.post(title: localized("Timer"), body: localized("Time is up"), id: "sandy.timer")
    }

    // MARK: - Pomodoro

    /// 25 minutes of work, 5 of rest, repeated until stopped. The same
    /// countdown machinery drives both phases; `pomodoroIsWork` tells the
    /// pane which label to show.
    func startPomodoro() {
        pomodoro = true
        pomodoroRounds = 0
        pomodoroIsWork = true
        startClock(seconds: TimeInterval(Self.workMinutes) * 60)
        Task { await Self.requestNotificationPermission() }
    }

    private func advancePomodoro() {
        let wasWork = pomodoroIsWork ?? true
        if wasWork { pomodoroRounds += 1 }
        pomodoroIsWork = !wasWork
        Self.post(
            title: localized("Pomodoro"),
            body: localized(wasWork ? "Break time" : "Focus time"),
            id: "sandy.pomodoro"
        )
        startClock(seconds: TimeInterval(wasWork ? Self.breakMinutes : Self.workMinutes) * 60)
    }

    // MARK: - Water

    /// A repeating reminder. Interval changes take effect on the next fire —
    /// rescheduling mid-wait is not worth the edge cases.
    func setWater(_ on: Bool) {
        waterTimer?.invalidate()
        waterTimer = nil
        waterOn = on
        guard on else { return }
        let seconds = TimeInterval(waterMinutes) * 60
        let timer = Timer(timeInterval: seconds, repeats: true) { _ in
            MainActor.assumeIsolated {
                Self.post(title: localized("Water"), body: localized("Time to drink water"), id: "sandy.water")
            }
        }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        waterTimer = timer
        Task { await Self.requestNotificationPermission() }
    }

    func setWaterMinutes(_ minutes: Int) {
        waterMinutes = minutes
        if waterOn { setWater(true) }
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
        setWater(false)
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

    private static func post(title: String, body: String, id: String) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "\(id).\(UUID().uuidString)", content: content, trigger: nil
        )
        center.add(request) { _ in }
    }
}
