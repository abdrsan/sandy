import Foundation
import UserNotifications

enum AgentNotificationAuthorization: Sendable {
    case notDetermined, allowed, denied, unavailable
}

@MainActor
protocol AgentNotificationDelivering: AnyObject {
    var onOpen: ((String) -> Void)? { get set }
    func requestPermission() async -> Bool
    func authorization() async -> AgentNotificationAuthorization
    func post(_ alert: AgentAlert)
    func cancelPending()
}

/// Notification text contains only the provider. Project paths and operation
/// details stay inside the panel, including when its privacy curtain is off.
@MainActor
final class AgentNotifications: NSObject, AgentNotificationDelivering, UNUserNotificationCenterDelegate {
    var onOpen: ((String) -> Void)?
    private let center: UNUserNotificationCenter?

    override init() {
        // UserNotifications requires a real application bundle. SwiftPM test
        // runners and source executables must not call current() and crash.
        center = Bundle.main.bundleURL.pathExtension == "app" ? .current() : nil
        super.init()
        center?.delegate = self
        updateCategories()
    }

    private func updateCategories() {
        let open = UNNotificationAction(identifier: "open", title: localized("Open Agent Session"), options: .foreground)
        center?.setNotificationCategories([
            UNNotificationCategory(identifier: "sandy.agent", actions: [open], intentIdentifiers: [])
        ])
    }

    func requestPermission() async -> Bool {
        guard let center else { return false }
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func authorization() async -> AgentNotificationAuthorization {
        guard let center else { return .unavailable }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .allowed
        case .denied: return .denied
        default: return .notDetermined
        }
    }

    func post(_ alert: AgentAlert) {
        guard let center else { return }
        updateCategories()
        let content = UNMutableNotificationContent()
        switch alert.kind {
        case .ready: content.title = localized("Answer Ready")
        case .waiting: content.title = localized("Your Input Is Needed")
        case .failed: content.title = localized("Agent Error")
        }
        content.body = alert.source.title
        content.sound = .default
        content.categoryIdentifier = "sandy.agent"
        content.userInfo = ["sandy.session": alert.sessionID]
        let request = UNNotificationRequest(identifier: "sandy.agent.\(UUID().uuidString)", content: content, trigger: nil)
        center.add(request) { _ in }
    }

    func cancelPending() {
        // Sandy currently has only agent notifications; never remove already
        // delivered alerts, whose links must remain usable after reconnecting.
        center?.removeAllPendingNotificationRequests()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier != UNNotificationDismissActionIdentifier,
              let id = response.notification.request.content.userInfo["sandy.session"] as? String else { return }
        await MainActor.run { self.onOpen?(id) }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
