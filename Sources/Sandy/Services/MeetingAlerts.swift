import AppKit
@preconcurrency import UserNotifications

/// System notifications for meetings that are about to start.
///
/// Rather than a timer that fires minutes before the meeting, each upcoming
/// event gets its own scheduled request, and `reload` in the calendar store
/// re-syncs the whole set — a rescheduled meeting then moves its alert with
/// no extra bookkeeping. Only ever enabled by the switch in Settings, which
/// is also where the permission prompt is raised.
@MainActor
final class MeetingAlerts {
    /// Same guard as everywhere else UserNotifications is touched: the call
    /// needs a real .app bundle, and tests must not crash on it.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleURL.pathExtension == "app" ? .current() : nil
    }

    private nonisolated static let prefix = "sandy.meeting."

    /// Only ever called from the Settings switch — the explicit ask.
    func requestPermission() async -> Bool {
        guard let center else { return false }
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Replaces every pending meeting alert with the current schedule.
    ///
    /// `Meeting` is not Sendable — it carries an NSColor — so the scheduling
    /// data is flattened into plain values before crossing into the center's
    /// callback queue.
    func sync(_ meetings: [CalendarStore.Meeting]) {
        guard let center else { return }
        struct Planned: Sendable { var id: String; var title: String; var fireIn: TimeInterval }
        let lead = TimeInterval(ConfigStore.shared.meetingAlertMinutes) * 60
        let planned: [Planned] = ConfigStore.shared.meetingAlerts ? meetings.prefix(20).compactMap { meeting in
            let fireIn = meeting.start.timeIntervalSinceNow - lead
            return fireIn > 0 ? Planned(id: meeting.id, title: meeting.title, fireIn: fireIn) : nil
        } : []
        center.getPendingNotificationRequests { requests in
            let ours = requests.map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)
            for item in planned {
                let content = UNMutableNotificationContent()
                content.title = localized("Upcoming Meeting")
                content.body = item.title
                content.sound = .default
                let request = UNNotificationRequest(
                    identifier: Self.prefix + item.id,
                    content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: item.fireIn, repeats: false)
                )
                center.add(request) { _ in }
            }
        }
    }
}
