import ActivityKit
import Charts
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
        if !context.isStale && !context.state.change.isEmpty {
            Text(context.state.change)
        } else {
            Text("--")
        }
    }

    func updatedLabel(context: ActivityViewContext<LiveActivityAttributes>) -> Text {
        Text(dateFormatter.string(from: context.state.date))
    }

    func bgLabel(context: ActivityViewContext<LiveActivityAttributes>) -> Text {
        if context.isStale {
            Text("--")
        } else {
            Text(context.state.bg)
        }
    }

    @ViewBuilder func trend(context: ActivityViewContext<LiveActivityAttributes>) -> some View {
        if context.isStale {
            Text("--")
        } else {
            if let trendSystemImage = context.state.trendSystemImage {
                Image(systemName: trendSystemImage)
            }
        }
    }

    @ViewBuilder func bgAndTrend(context: ActivityViewContext<LiveActivityAttributes>) -> some View {
        if context.isStale {
            Text("--")
        } else {
            HStack {
                Text(context.state.bg).fontWeight(.bold)
                if let trendSystemImage = context.state.trendSystemImage {
                    Image(systemName: trendSystemImage)
                }
            }
        }
    }

    @ViewBuilder func chart(context: ActivityViewContext<LiveActivityAttributes>) -> some View {
        if context.isStale {
            Text("--")
        } else {
            Chart {
                ForEach(context.state.chart.indices, id: \.self) { index in
                    LineMark(
                        x: .value("Time", context.state.chartDate[index] ?? Date()),
                        y: .value("Value", context.state.chart[index] ?? 0)
                    ).foregroundStyle(Color.green.gradient).symbolSize(12)
                }
            }.chartPlotStyle { plotContent in
                plotContent.background(.gray.opacity(0.1))
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }.foregroundStyle(Color.white)
            .chartXAxis {
                AxisMarks(position: .automatic)
            }.foregroundStyle(Color.white)
        }
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivityAttributes.self) { context in
            // Lock screen/banner UI goes here

            HStack(spacing: 2) {
                VStack {
                    chart(context: context).frame(width: UIScreen.main.bounds.width / 1.7)
                }.padding()
                Divider()
                VStack {
                    ZStack {
                        Circle().fill(Color.green.opacity(0.7))
                            .frame(width: UIScreen.main.bounds.width / 5, height: UIScreen.main.bounds.height / 5).clipped()
                        VStack {
                            bgAndTrend(context: context).imageScale(.small).font(.title2)
                            changeLabel(context: context).font(.callout)
                        }
                    }.padding()
                    updatedLabel(context: context).font(.caption)
                }
            }
            .privacySensitive()
            .imageScale(.small)
            .padding(.all, 15)
            .background(Color.white.opacity(0.2))
            .foregroundColor(Color.white)
            .activityBackgroundTint(Color.cyan.opacity(0.3))
            .activitySystemActionForegroundColor(Color.black)

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
                    updatedLabel(context: context).font(.caption).foregroundStyle(Color.secondary)
                        .padding(.bottom, 5)
                    chart(context: context)
                }
            } compactLeading: {
                HStack(spacing: 1) {
                    bgAndTrend(context: context)
                }.bold().imageScale(.small).padding(.leading, 5)
            } compactTrailing: {
                changeLabel(context: context).padding(.trailing, 5)
            } minimal: {
                bgLabel(context: context).bold()
            }
            .widgetURL(URL(string: "freeaps-x://"))
            .keylineTint(Color.cyan.opacity(0.5))
        }
    }
}

// private extension LiveActivityAttributes {
//    static var preview: LiveActivityAttributes {
//        LiveActivityAttributes(startDate: Date())
//    }
// }
//
// private extension LiveActivityAttributes.ContentState {
//    static var test: LiveActivityAttributes.ContentState {
//        LiveActivityAttributes.ContentState(bg: "100", trendSystemImage: "arrow.right", change: "+2", date: Date())
//    }
// }
//
// #Preview("Notification", as: .content, using: LiveActivityAttributes.preview) {
//    LiveActivity()
// } contentStates: {
//    LiveActivityAttributes.ContentState.test
// }
