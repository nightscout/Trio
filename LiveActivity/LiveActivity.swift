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

    private var bolusFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.decimalSeparator = "."
        return formatter
    }

    private var carbsFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }

    func changeLabel(context: ActivityViewContext<LiveActivityAttributes>) -> Text {
        if !context.isStale && !context.state.change.isEmpty {
            Text(context.state.change)
        } else {
            Text("--")
        }
    }

    func updatedLabel(context: ActivityViewContext<LiveActivityAttributes>) -> Text {
        Text("Updated: \(dateFormatter.string(from: context.state.date))").italic()
    }

    func bgLabel(context: ActivityViewContext<LiveActivityAttributes>) -> Text {
        if context.isStale {
            Text("--")
        } else {
            Text(context.state.bg).fontWeight(.bold)
        }
    }

    @ViewBuilder func mealLabel(context: ActivityViewContext<LiveActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 1, content: {
            HStack {
                Text("COB: ").font(.caption)
                Text(
                    (carbsFormatter.string(from: context.state.cob as NSNumber) ?? "--") +
                        NSLocalizedString(" g", comment: "grams of carbs")
                ).font(.caption).fontWeight(.bold)
            }
            HStack {
                Text("IOB: ").font(.caption)
                Text(
                    (bolusFormatter.string(from: context.state.iob as NSNumber) ?? "--") +
                        NSLocalizedString(" U", comment: "Unit in number of units delivered (keep the space character!)")
                ).font(.caption).fontWeight(.bold)
            }
        })
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

    @ViewBuilder func bobble(context: ActivityViewContext<LiveActivityAttributes>) -> some View {
        @State var angularGradient = AngularGradient(colors: [
            Color(red: 0.7215686275, green: 0.3411764706, blue: 1),
            Color(red: 0.6235294118, green: 0.4235294118, blue: 0.9803921569),
            Color(red: 0.4862745098, green: 0.5450980392, blue: 0.9529411765),
            Color(red: 0.3411764706, green: 0.6666666667, blue: 0.9254901961),
            Color(red: 0.262745098, green: 0.7333333333, blue: 0.9137254902),
            Color(red: 0.7215686275, green: 0.3411764706, blue: 1)
        ], center: .center, startAngle: .degrees(270), endAngle: .degrees(-90))
        let triangleColor = Color(red: 0.262745098, green: 0.7333333333, blue: 0.9137254902)

        WidgetBobble(gradient: angularGradient, color: triangleColor)
            .rotationEffect(.degrees(context.state.rotationDegrees))
    }

    @ViewBuilder func chart(context: ActivityViewContext<LiveActivityAttributes>) -> some View {
        if context.isStale {
            Text("No data available")
        } else {
            Chart {
                ForEach(context.state.chart.indices, id: \.self) { index in
                    let currentValue = context.state.chart[index]
                    if currentValue > context.state.highGlucose {
                        PointMark(
                            x: .value("Time", context.state.chartDate[index] ?? Date()),
                            y: .value("Value", currentValue)
                        ).foregroundStyle(Color.orange.gradient).symbolSize(12)
                    } else if currentValue < context.state.lowGlucose {
                        PointMark(
                            x: .value("Time", context.state.chartDate[index] ?? Date()),
                            y: .value("Value", currentValue)
                        ).foregroundStyle(Color.red.gradient).symbolSize(12)
                    } else {
                        PointMark(
                            x: .value("Time", context.state.chartDate[index] ?? Date()),
                            y: .value("Value", currentValue)
                        ).foregroundStyle(Color.green.gradient).symbolSize(12)
                    }
                }
            }.chartPlotStyle { plotContent in
                plotContent.background(.cyan.opacity(0.1))
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel().foregroundStyle(Color.white)
                    AxisGridLine(stroke: .init(lineWidth: 0.1, dash: [2, 3])).foregroundStyle(Color.white)
                }
            }
            .chartXAxis {
                AxisMarks(position: .automatic) { _ in
                    AxisValueLabel().foregroundStyle(Color.white)
                    AxisGridLine(stroke: .init(lineWidth: 0.1, dash: [2, 3])).foregroundStyle(Color.white)
                }
            }
        }
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivityAttributes.self) { context in
            // Lock screen/banner UI goes here
            if context.state.lockScreenView == "Simple" {
                HStack(spacing: 3) {
                   bgAndTrend(context: context).font(.title)
                   Spacer()
                   VStack(alignment: .trailing, spacing: 5) {
                       changeLabel(context: context).font(.title3)
                       updatedLabel(context: context).font(.caption).foregroundStyle(.black.opacity(0.7))
                   }
               }
               .privacySensitive()
               .imageScale(.small)
               .padding(.all, 15)
               .background(Color.white.opacity(0.2))
               .foregroundColor(Color.black)
               .activityBackgroundTint(Color.cyan.opacity(0.2))
               .activitySystemActionForegroundColor(Color.black)
            } else {
                HStack(spacing: 2) {
                    VStack {
                        chart(context: context).frame(width: UIScreen.main.bounds.width / 1.8)
                    }.padding(.all, 15)
                    Divider().foregroundStyle(Color.white)
                    VStack(alignment: .center) {
                        Spacer()
                        ZStack {
                            bobble(context: context)
                                .scaleEffect(0.6)
                                .clipped()
                            VStack {
                                bgLabel(context: context).font(.title2).imageScale(.small)
                                changeLabel(context: context).font(.callout)
                            }
                        }.scaleEffect(0.85).offset(y: 15)
                        mealLabel(context: context).padding(.bottom, 8)
                        updatedLabel(context: context).font(.caption).padding(.bottom, 50)
                    }
                }
                .privacySensitive()
                .imageScale(.small)
                .background(Color.white.opacity(0.2))
                .foregroundColor(Color.white)
                .activityBackgroundTint(Color.black.opacity(0.7))
                .activitySystemActionForegroundColor(Color.white)
            }
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
                    chart(context: context)
                }
                DynamicIslandExpandedRegion(.center) {
                    updatedLabel(context: context).font(.caption).foregroundStyle(Color.secondary)
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
