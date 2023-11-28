import ActivityKit
import SwiftUI
import WidgetKit

struct LiveActivity: Widget {
    let dateFormatter: DateFormatter = {
        var f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    func changeLabel(context: ActivityViewContext<LiveActivityAttributes>) -> Text {
        if let change = context.state.change {
            Text("\(change > 0 ? "+" : "")\(change)")
        } else {
            Text("--")
        }
    }

    func updatedLabel(context: ActivityViewContext<LiveActivityAttributes>) -> Text {
        Text("Updated: \(dateFormatter.string(from: context.state.date))")
    }

    func bgLabel(context: ActivityViewContext<LiveActivityAttributes>) -> Text {
        if context.isStale {
            Text("--")
        } else {
            Text("\(context.state.bg)")
        }
    }

    @ViewBuilder func bgAndTrend(context: ActivityViewContext<LiveActivityAttributes>) -> some View {
        if context.isStale {
            Text("--")
        } else {
            Text("\(context.state.bg)")
            if let trendSystemImage = context.state.trendSystemImage {
                Image(systemName: trendSystemImage)
            }
        }
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivityAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack(alignment: .trailing, spacing: 0) {
                HStack(alignment: .top) {
                    HStack(alignment: .center, spacing: 3) {
                        bgAndTrend(context: context).font(.title)
                    }
                    Spacer()
                    changeLabel(context: context).font(.title3)
                }
                .imageScale(.small)
                updatedLabel(context: context).font(.caption).offset(y: -3)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .activityBackgroundTint(Color.cyan.opacity(0.2))
            .activitySystemActionForegroundColor(Color.white)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 3) {
                        bgAndTrend(context: context)
                    }.imageScale(.small).font(.title).padding(.leading, 5)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    changeLabel(context: context).font(.title).padding(.trailing, 5)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    updatedLabel(context: context).font(.caption)
                }
            } compactLeading: {
                HStack(spacing: 1) {
                    bgAndTrend(context: context)
                }.bold().imageScale(.small)
            } compactTrailing: {
                changeLabel(context: context)
            } minimal: {
                bgLabel(context: context).bold()
            }
            .widgetURL(URL(string: "freeaps-x://"))
            .keylineTint(Color.cyan.opacity(0.5))
        }
    }
}

private extension LiveActivityAttributes {
    static var preview: LiveActivityAttributes {
        LiveActivityAttributes(startDate: Date())
    }
}

private extension LiveActivityAttributes.ContentState {
    static var test: LiveActivityAttributes.ContentState {
        LiveActivityAttributes.ContentState(bg: "100", trendSystemImage: "arrow.right", change: 2, date: Date())
    }
}

#Preview("Notification", as: .content, using: LiveActivityAttributes.preview) {
    LiveActivity()
} contentStates: {
    LiveActivityAttributes.ContentState.test
}
