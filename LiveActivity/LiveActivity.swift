import ActivityKit
import Charts
import SwiftUI
import WidgetKit

private enum Size {
    case minimal
    case compact
    case expanded
}

struct LiveActivity: Widget {
    private let dateFormatter: DateFormatter = {
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

    @ViewBuilder private func changeLabel(context: ActivityViewContext<LiveActivityAttributes>) -> some View {
        if !context.state.change.isEmpty {
            if context.isStale {
                Text(context.state.change).foregroundStyle(.primary.opacity(0.5))
                    .strikethrough(pattern: .solid, color: .red.opacity(0.6))
            } else {
                Text(context.state.change)
            }
        } else {
            Text("--")
        }
    }

    @ViewBuilder func mealLabel(
        context _: ActivityViewContext<LiveActivityAttributes>,
        additionalState: LiveActivityAttributes.ContentAdditionalState
    ) -> some View {
        VStack(alignment: .leading, spacing: 1, content: {
            HStack {
                Text("COB: ").font(.caption)
                Text(
                    (carbsFormatter.string(from: additionalState.cob as NSNumber) ?? "--") +
                        NSLocalizedString(" g", comment: "grams of carbs")
                ).font(.caption).fontWeight(.bold)
            }
            HStack {
                Text("IOB: ").font(.caption)
                Text(
                    (bolusFormatter.string(from: additionalState.iob as NSNumber) ?? "--") +
                        NSLocalizedString(" U", comment: "Unit in number of units delivered (keep the space character!)")
                ).font(.caption).fontWeight(.bold)
            }
        })
    }

    @ViewBuilder func trend(context: ActivityViewContext<LiveActivityAttributes>) -> some View {
        if context.isStale {
            Text("--")
        } else {
            if let trendSystemImage = context.state.direction {
                Image(systemName: trendSystemImage)
            }
        }
    }

    private func expiredLabel() -> some View {
        Text("Live Activity Expired. Open Trio to Refresh")
            .minimumScaleFactor(0.01)
    }

    private func updatedLabel(context: ActivityViewContext<LiveActivityAttributes>) -> Text {
        let text = Text("Updated: \(dateFormatter.string(from: context.state.date))")
        if context.isStale {
            if #available(iOSApplicationExtension 17.0, *) {
                return text.bold().foregroundStyle(.red)
            } else {
                return text.bold().foregroundColor(.red)
            }
        } else {
            return text
        }
    }

    private func bgLabel(context: ActivityViewContext<LiveActivityAttributes>) -> Text {
        Text(context.state.bg)
            .fontWeight(.bold)
            .strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))
    }

    private func bgAndTrend(context: ActivityViewContext<LiveActivityAttributes>, size: Size) -> (some View, Int) {
        var characters = 0

        let bgText = context.state.bg
        characters += bgText.count

        // narrow mode is for the minimal dynamic island view
        // there is not enough space to show all three arrow there
        // and everything has to be squeezed together to some degree
        // only display the first arrow character and make it red in case there were more characters
        var directionText: String?
        var warnColor: Color?
        if let direction = context.state.direction {
            if size == .compact || size == .minimal {
                directionText = String(direction[direction.startIndex ... direction.startIndex])

                if direction.count > 1 {
                    warnColor = Color.red
                }
            } else {
                directionText = direction
            }

            characters += directionText!.count
        }

        let spacing: CGFloat
        switch size {
        case .minimal: spacing = -1
        case .compact: spacing = 0
        case .expanded: spacing = 3
        }

        let stack = HStack(spacing: spacing) {
            Text(bgText)
                .strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))
            if let direction = directionText {
                let text = Text(direction)
                switch size {
                case .minimal:
                    let scaledText = text.scaleEffect(x: 0.7, y: 0.7, anchor: .leading)
                    if let warnColor {
                        scaledText.foregroundStyle(warnColor)
                    } else {
                        scaledText
                    }
                case .compact:
                    text.scaleEffect(x: 0.8, y: 0.8, anchor: .leading).padding(.trailing, -3)

                case .expanded:
                    text.scaleEffect(x: 0.7, y: 0.7, anchor: .leading).padding(.trailing, -5)
                }
            }
        }
        .foregroundStyle(
            context.state.detailedViewState == nil ? (context.isStale ? Color.primary.opacity(0.5) : Color.primary) :
                (context.isStale ? Color.white.opacity(0.5) : Color.white)
        )

        return (stack, characters)
    }

    @ViewBuilder func chart(
        context: ActivityViewContext<LiveActivityAttributes>,
        additionalState: LiveActivityAttributes.ContentAdditionalState
    ) -> some View {
        if context.isStale {
            Text("No data available")
        } else {
            Chart {
                ForEach(additionalState.chart.indices, id: \.self) { index in
                    let currentValue = additionalState.chart[index]
                    if currentValue > additionalState.highGlucose {
                        PointMark(
                            x: .value("Time", additionalState.chartDate[index] ?? Date()),
                            y: .value("Value", currentValue)
                        ).foregroundStyle(Color.orange.gradient).symbolSize(12)
                    } else if currentValue < additionalState.lowGlucose {
                        PointMark(
                            x: .value("Time", additionalState.chartDate[index] ?? Date()),
                            y: .value("Value", currentValue)
                        ).foregroundStyle(Color.red.gradient).symbolSize(12)
                    } else {
                        PointMark(
                            x: .value("Time", additionalState.chartDate[index] ?? Date()),
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
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .narrow)), anchor: .top)
                        .foregroundStyle(Color.white)
                    AxisGridLine(stroke: .init(lineWidth: 0.1, dash: [2, 3])).foregroundStyle(Color.white)
                }
            }
        }
    }

    @ViewBuilder func content(context: ActivityViewContext<LiveActivityAttributes>) -> some View {
        // Lock screen/banner UI goes here
        if let detailedViewState = context.state.detailedViewState {
            HStack(spacing: 2) {
                VStack {
                    chart(context: context, additionalState: detailedViewState).frame(width: UIScreen.main.bounds.width / 1.8)
                }.padding(.all, 15)
                Divider().foregroundStyle(Color.white)
                VStack(alignment: .center) {
                    Spacer()
                    ZStack {
                        VStack {
                            bgAndTrend(context: context, size: .expanded).0.font(.largeTitle)
                            changeLabel(context: context).font(.callout)
                        }.frame(width: 130, height: 130)
                    }.scaleEffect(0.85).offset(y: 30)
                    mealLabel(context: context, additionalState: detailedViewState).padding(.bottom, 8)
                    updatedLabel(context: context).font(.caption).padding(.bottom, 70)
                }
            }
            .privacySensitive()
            .imageScale(.small)
            .background(Color.white.opacity(0.2))
            .foregroundColor(Color.white)
            .activityBackgroundTint(Color.black.opacity(0.7))
            .activitySystemActionForegroundColor(Color.white)
        } else {
            Group {
                if context.state.isInitialState {
                    // add vertical and horizontal spacers around the label to ensure that the live activity view gets filled completely
                    HStack {
                        Spacer()
                        VStack {
                            Spacer()
                            expiredLabel()
                            Spacer()
                        }
                        Spacer()
                    }
                } else {
                    HStack(spacing: 3) {
                        bgAndTrend(context: context, size: .expanded).0.font(.title)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 5) {
                            changeLabel(context: context).font(.title3)
                            updatedLabel(context: context).font(.caption).foregroundStyle(.primary.opacity(0.7))
                        }
                    }
                }
            }
            .privacySensitive()
            .padding(.all, 15)
            // Semantic BackgroundStyle and Color values work here. They adapt to the given interface style (light mode, dark mode)
            // Semantic UIColors do NOT (as of iOS 17.1.1). Like UIColor.systemBackgroundColor (it does not adapt to changes of the interface style)
            // The colorScheme environment varaible that is usually used to detect dark mode does NOT work here (it reports false values)
            .foregroundStyle(Color.primary)
            .background(BackgroundStyle.background.opacity(0.4))
            .activityBackgroundTint(Color.clear)
        }
    }

    func dynamicIsland(context: ActivityViewContext<LiveActivityAttributes>) -> DynamicIsland {
        DynamicIsland {
            // Expanded UI goes here.  Compose the expanded UI through
            // various regions, like leading/trailing/center/bottom
            DynamicIslandExpandedRegion(.leading) {
                bgAndTrend(context: context, size: .expanded).0.font(.title2).padding(.leading, 5)
            }
            DynamicIslandExpandedRegion(.trailing) {
                changeLabel(context: context).font(.title2).padding(.trailing, 5)
            }
            DynamicIslandExpandedRegion(.bottom) {
                if context.state.isInitialState {
                    expiredLabel()
                } else if let detailedViewState = context.state.detailedViewState {
                    chart(context: context, additionalState: detailedViewState)
                } else {
                    Group {
                        updatedLabel(context: context).font(.caption).foregroundStyle(Color.secondary)
                    }
                    .frame(
                        maxHeight: .infinity,
                        alignment: .bottom
                    )
                }
            }
            DynamicIslandExpandedRegion(.center) {
                if context.state.detailedViewState != nil {
                    updatedLabel(context: context).font(.caption).foregroundStyle(Color.secondary)
                }
            }
        } compactLeading: {
            bgAndTrend(context: context, size: .compact).0.padding(.leading, 4)
        } compactTrailing: {
            changeLabel(context: context).padding(.trailing, 4)
        } minimal: {
            let (_label, characterCount) = bgAndTrend(context: context, size: .minimal)

            let label = _label.padding(.leading, 7).padding(.trailing, 3)

            if characterCount < 4 {
                label
            } else if characterCount < 5 {
                label.fontWidth(.condensed)
            } else {
                label.fontWidth(.compressed)
            }
        }
        .widgetURL(URL(string: "Trio://"))
        .keylineTint(Color.purple)
        .contentMargins(.horizontal, 0, for: .minimal)
        .contentMargins(.trailing, 0, for: .compactLeading)
        .contentMargins(.leading, 0, for: .compactTrailing)
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivityAttributes.self, content: self.content, dynamicIsland: self.dynamicIsland)
    }
}

private extension LiveActivityAttributes {
    static var preview: LiveActivityAttributes {
        LiveActivityAttributes(startDate: Date())
    }
}

private extension LiveActivityAttributes.ContentState {
    // 0 is the widest digit. Use this to get an upper bound on text width.

    // Use mmol/l notation with decimal point as well for the same reason, it uses up to 4 characters, while mg/dl uses up to 3
    static var testWide: LiveActivityAttributes.ContentState {
        LiveActivityAttributes.ContentState(
            bg: "00.0",
            direction: "→",
            change: "+0.0",
            date: Date(),
            detailedViewState: nil,
            isInitialState: false
        )
    }

    static var testVeryWide: LiveActivityAttributes.ContentState {
        LiveActivityAttributes.ContentState(
            bg: "00.0",
            direction: "↑↑",
            change: "+0.0",
            date: Date(),
            detailedViewState: nil,
            isInitialState: false
        )
    }

    static var testSuperWide: LiveActivityAttributes.ContentState {
        LiveActivityAttributes.ContentState(
            bg: "00.0",
            direction: "↑↑↑",
            change: "+0.0",
            date: Date(),
            detailedViewState: nil,
            isInitialState: false
        )
    }

    // 2 characters for BG, 1 character for change is the minimum that will be shown
    static var testNarrow: LiveActivityAttributes.ContentState {
        LiveActivityAttributes.ContentState(
            bg: "00",
            direction: "↑",
            change: "+0",
            date: Date(),
            detailedViewState: nil,
            isInitialState: false
        )
    }

    static var testMedium: LiveActivityAttributes.ContentState {
        LiveActivityAttributes.ContentState(
            bg: "000",
            direction: "↗︎",
            change: "+00",
            date: Date(),
            detailedViewState: nil,
            isInitialState: false
        )
    }

    static var testExpired: LiveActivityAttributes.ContentState {
        LiveActivityAttributes.ContentState(
            bg: "--",
            direction: nil,
            change: "--",
            date: Date().addingTimeInterval(-60 * 60),
            detailedViewState: nil,
            isInitialState: true
        )
    }
}

@available(iOS 17.0, iOSApplicationExtension 17.0, *)
#Preview("Notification", as: .content, using: LiveActivityAttributes.preview) {
    LiveActivity()
} contentStates: {
    LiveActivityAttributes.ContentState.testSuperWide
    LiveActivityAttributes.ContentState.testVeryWide
    LiveActivityAttributes.ContentState.testWide
    LiveActivityAttributes.ContentState.testMedium
    LiveActivityAttributes.ContentState.testNarrow
    LiveActivityAttributes.ContentState.testExpired
}
