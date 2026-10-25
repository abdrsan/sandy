import ActivityKit
struct AgentActivityAttributes: ActivityAttributes {
    struct ContentState: Codable,Hashable { var working:Int; var waiting:Int; var status:String }
}
