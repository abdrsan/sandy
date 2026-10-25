import ActivityKit
import Foundation
extension PhoneStore {
    func startLiveStatus() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard Activity<AgentActivityAttributes>.activities.isEmpty else { return }
        if let activity=try? Activity<AgentActivityAttributes>.request(attributes:AgentActivityAttributes(),content:content(),pushType:.token) {
            Task { for await token in activity.pushTokenUpdates { await self.registerLivePush(token) } }
        }
    }
    func updateLiveStatus() {
        let value=content()
        Task { for activity in Activity<AgentActivityAttributes>.activities { await activity.update(value) } }
    }
    private func content() -> ActivityContent<AgentActivityAttributes.ContentState> {
        let latest=Dictionary(activities.map{($0.session,$0)},uniquingKeysWith:{$1})
        let working=latest.values.filter{$0.state=="working"}.count
        let waiting=approvals.count
        return ActivityContent(state:.init(working:working,waiting:waiting,status:waiting>0 ? "\(waiting) need your approval":"\(working) working"),staleDate:Date().addingTimeInterval(45))
    }
}
