import ActivityKit
import SwiftUI
import WidgetKit
@main struct SandyWidgets: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for:AgentActivityAttributes.self) { context in
            HStack { Image(systemName:"sparkles");Text("Sandy");Spacer();Text(context.state.status) }.padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Label("Sandy",systemImage:"sparkles") }
                DynamicIslandExpandedRegion(.trailing) { Text("\(context.state.working) working") }
                DynamicIslandExpandedRegion(.bottom) { Text(context.isStale ? "Open Sandy to refresh" : context.state.status) }
            } compactLeading: { Image(systemName:"sparkles") } compactTrailing: { Text("\(context.state.waiting)") }
              minimal: { Image(systemName:context.state.waiting>0 ? "exclamationmark.circle":"sparkles") }
        }
    }
}
