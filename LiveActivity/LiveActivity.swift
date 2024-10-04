import ActivityKit
import Charts
import Foundation
import SwiftUI
import WidgetKit

private enum Size {
    case minimal
    case compact
    case expanded
}

enum GlucoseUnits: String, Equatable {
    case mgdL = "mg/dL"
    case mmolL = "mmol/L"

    static let exchangeRate: Decimal = 0.0555
}

enum GlucoseColorScheme: String, Equatable {
    case staticColor
    case dynamicColor
}

func rounded(_ value: Decimal, scale: Int, roundingMode: NSDecimalNumber.RoundingMode) -> Decimal {
    var result = Decimal()
    var toRound = value
    NSDecimalRound(&result, &toRound, scale, roundingMode)
    return result
}

extension Int {
    var asMmolL: Decimal {
        rounded(Decimal(self) * GlucoseUnits.exchangeRate, scale: 1, roundingMode: .plain)
    }

    var formattedAsMmolL: String {
        NumberFormatter.glucoseFormatter.string(from: asMmolL as NSDecimalNumber) ?? "\(asMmolL)"
    }
}

extension Decimal {
    var asMmolL: Decimal {
        rounded(self * GlucoseUnits.exchangeRate, scale: 1, roundingMode: .plain)
    }

    var asMgdL: Decimal {
        rounded(self / GlucoseUnits.exchangeRate, scale: 0, roundingMode: .plain)
    }

    var formattedAsMmolL: String {
        NumberFormatter.glucoseFormatter.string(from: asMmolL as NSDecimalNumber) ?? "\(asMmolL)"
    }
}

extension NumberFormatter {
    static let glucoseFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter
    }()
}

struct LiveActivity: Widget {
    // Helper function to decide how to pick the glucose color
    func getDynamicGlucoseColor(
        glucoseValue: Decimal,
        highGlucoseColorValue: Decimal,
        lowGlucoseColorValue: Decimal,
        targetGlucose: Decimal,
        glucoseColorScheme: String,
        offset: Decimal
    ) -> Color {
        // Convert Decimal to Int for high and low glucose values
        let lowGlucose = lowGlucoseColorValue - offset
        let highGlucose = highGlucoseColorValue + (offset * 1.75)
        let targetGlucose = targetGlucose

        // Only use calculateHueBasedGlucoseColor if the setting is enabled in preferences
        if glucoseColorScheme == "dynamicColor" {
            return calculateHueBasedGlucoseColor(
                glucoseValue: glucoseValue,
                highGlucose: highGlucose,
                lowGlucose: lowGlucose,
                targetGlucose: targetGlucose
            )
        }
        // Otheriwse, use static (orange = high, red = low, green = range)
        else {
            if glucoseValue > highGlucose {
                return Color.orange
            } else if glucoseValue < lowGlucose {
                return Color.red
            } else {
                return Color.green
            }
        }
    }

    // Dynamic color - Define the hue values for the key points
    // We'll shift color gradually one glucose point at a time
    // We'll shift through the rainbow colors of ROY-G-BIV from low to high
    // Start at red for lowGlucose, green for targetGlucose, and violet for highGlucose
    func calculateHueBasedGlucoseColor(
        glucoseValue: Decimal,
        highGlucose: Decimal,
        lowGlucose: Decimal,
        targetGlucose: Decimal
    ) -> Color {
        let redHue: CGFloat = 0.0 / 360.0 // 0 degrees
        let greenHue: CGFloat = 120.0 / 360.0 // 120 degrees
        let purpleHue: CGFloat = 270.0 / 360.0 // 270 degrees

        // Calculate the hue based on the bgLevel
        var hue: CGFloat
        if glucoseValue <= lowGlucose {
            hue = redHue
        } else if glucoseValue >= highGlucose {
            hue = purpleHue
        } else if glucoseValue <= targetGlucose {
            // Interpolate between red and green
            let ratio = CGFloat(truncating: (glucoseValue - lowGlucose) / (targetGlucose - lowGlucose) as NSNumber)

            hue = redHue + ratio * (greenHue - redHue)
        } else {
            // Interpolate between green and purple
            let ratio = CGFloat(truncating: (glucoseValue - targetGlucose) / (highGlucose - targetGlucose) as NSNumber)
            hue = greenHue + ratio * (purpleHue - greenHue)
        }
        // Return the color with full saturation and brightness
        let color = Color(hue: hue, saturation: 0.6, brightness: 0.9)
        return color
    }

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
            Text(context.state.change).foregroundStyle(.primary).font(.headline)
                .strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))
        } else {
            Text("--")
        }
    }

    @ViewBuilder func mealLabel(
        context: ActivityViewContext<LiveActivityAttributes>,
        additionalState: LiveActivityAttributes.ContentAdditionalState
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1, content: {
                HStack {
                    Image(systemName: "fork.knife")
                        .font(.title3)
                        .foregroundColor(.yellow)
                }
                HStack {
                    Image(systemName: "syringe.fill")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
            })
            VStack(alignment: .trailing, spacing: 1, content: {
                HStack {
                    Text(
                        carbsFormatter.string(from: additionalState.cob as NSNumber) ?? "--"
                    ).fontWeight(.bold).font(.headline).strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))
                    Text(NSLocalizedString(" g", comment: "grams of carbs")).foregroundStyle(.secondary).font(.footnote)
                }
                HStack {
                    Text(
                        bolusFormatter.string(from: additionalState.iob as NSNumber) ?? "--"
                    ).font(.headline).fontWeight(.bold).strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))
                    Text(NSLocalizedString(" U", comment: "Unit in number of units delivered (keep the space character!)"))
                        .foregroundStyle(.secondary).font(.footnote)
                }
            })
            VStack(alignment: .trailing, spacing: 1, content: {
                if additionalState.isOverrideActive {
                    Image(systemName: "person.crop.circle.fill.badge.checkmark")
                        .font(.title3)
                }
            })
        }
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
            .font(.caption2)
        if context.isStale {
            // foregroundStyle is not available in <iOS 17 hence the check here
            if #available(iOSApplicationExtension 17.0, *) {
                return text.bold().foregroundStyle(.red)
            } else {
                return text.bold().foregroundColor(.red)
            }
        } else {
            if #available(iOSApplicationExtension 17.0, *) {
                return text.bold().foregroundStyle(.secondary)
            } else {
                return text.bold().foregroundColor(.red)
            }
        }
    }

    @ViewBuilder private func bgLabel(
        context: ActivityViewContext<LiveActivityAttributes>,
        additionalState: LiveActivityAttributes.ContentAdditionalState
    ) -> some View {
        HStack(alignment: .center) {
            Text(context.state.bg)
                .fontWeight(.bold)
                .font(.largeTitle)
                .strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))
            Text(additionalState.unit).foregroundStyle(.secondary).font(.subheadline).offset(x: -5, y: 5)
        }
    }

    private func bgAndTrend(
        context: ActivityViewContext<LiveActivityAttributes>,
        size: Size,
        hasStaticColorScheme: Bool,
        glucoseColor: Color
    ) -> (some View, Int) {
        var characters = 0

        let bgText = context.state.bg
        characters += bgText.count

        // narrow mode is for the minimal dynamic island view
        // there is not enough space to show all three arrow there
        // and everything has to be squeezed together to some degree
        // only display the first arrow character
        var directionText: String?
        if let direction = context.state.direction {
            if size == .compact {
                directionText = String(direction[direction.startIndex ... direction.startIndex])
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
                .foregroundColor(hasStaticColorScheme ? .primary : glucoseColor)
                .strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))

            if let direction = directionText {
                let text = Text(direction)
                switch size {
                case .minimal:
                    let scaledText = text.scaleEffect(x: 0.7, y: 0.7, anchor: .leading)
                    scaledText.foregroundStyle(hasStaticColorScheme ? .primary : glucoseColor)
                case .compact:
                    text.scaleEffect(x: 0.8, y: 0.8, anchor: .leading).padding(.trailing, -3)

                case .expanded:
                    text.scaleEffect(x: 0.7, y: 0.7, anchor: .leading).padding(.trailing, -5)
                }
            }
        }
        .foregroundColor(context.isStale ? Color.primary.opacity(0.5) : (hasStaticColorScheme ? .primary : glucoseColor))

        return (stack, characters)
    }

    @ViewBuilder func trendArrow(
        context: ActivityViewContext<LiveActivityAttributes>,
        additionalState: LiveActivityAttributes.ContentAdditionalState
    ) -> some View {
        let gradient = LinearGradient(colors: [
            Color(red: 0.6235294118, green: 0.4235294118, blue: 0.9803921569),
            Color(red: 0.4862745098, green: 0.5450980392, blue: 0.9529411765),
            Color(red: 0.3411764706, green: 0.6666666667, blue: 0.9254901961),
            Color(red: 0.262745098, green: 0.7333333333, blue: 0.9137254902)
        ], startPoint: .leading, endPoint: .trailing)

        if !context.isStale {
            Image(systemName: "arrow.right")
                .font(.title)
                .rotationEffect(.degrees(additionalState.rotationDegrees))
                .foregroundStyle(gradient)
        }
    }

    @ViewBuilder func chart(
        context: ActivityViewContext<LiveActivityAttributes>,
        additionalState: LiveActivityAttributes.ContentAdditionalState
    ) -> some View {
        if context.isStale {
            Text("No data available")
        } else {
            // Determine scale
            let min = min(additionalState.chart.min() ?? 45, 40) - 20
            let max = max(additionalState.chart.max() ?? 270, 300) + 50

            let yAxisRuleMarkMin = additionalState.unit == "mg/dL" ? context.state.lowGlucose : context.state.lowGlucose
                .asMmolL
            let yAxisRuleMarkMax = additionalState.unit == "mg/dL" ? context.state.highGlucose : context.state.highGlucose
                .asMmolL

            // TODO: grab target from proper targets, do not hard code.
            let highColor = getDynamicGlucoseColor(
                glucoseValue: yAxisRuleMarkMax,
                highGlucoseColorValue: yAxisRuleMarkMax,
                lowGlucoseColorValue: yAxisRuleMarkMin,
                targetGlucose: additionalState.unit == "mg/dL" ? Decimal(90) : Decimal(90).asMmolL,
                glucoseColorScheme: context.state.glucoseColorScheme,
                offset: additionalState.unit == "mg/dL" ? Decimal(20) : Decimal(20).asMmolL
            )

            // TODO: grab target from proper targets, do not hard code.
            let lowColor = getDynamicGlucoseColor(
                glucoseValue: yAxisRuleMarkMin,
                highGlucoseColorValue: yAxisRuleMarkMax,
                lowGlucoseColorValue: yAxisRuleMarkMin,
                targetGlucose: additionalState.unit == "mg/dL" ? Decimal(90) : Decimal(90).asMmolL,
                glucoseColorScheme: context.state.glucoseColorScheme,
                offset: additionalState.unit == "mg/dL" ? Decimal(20) : Decimal(20).asMmolL
            )

            Chart {
                RuleMark(y: .value("High", yAxisRuleMarkMax))
                    .foregroundStyle(highColor)
                    .lineStyle(.init(lineWidth: 0.5, dash: [5]))
                RuleMark(y: .value("Low", yAxisRuleMarkMin))
                    .foregroundStyle(lowColor)
                    .lineStyle(.init(lineWidth: 0.5, dash: [5]))

                ForEach(additionalState.chart.indices, id: \.self) { index in
                    let currentValue = additionalState.chart[index]
                    let displayValue = additionalState.unit == "mg/dL" ? currentValue : currentValue.asMmolL

                    // TODO: grab target from proper targets, do not hard code.
                    let pointMarkColor = self.getDynamicGlucoseColor(
                        glucoseValue: currentValue,
                        highGlucoseColorValue: context.state.highGlucose,
                        lowGlucoseColorValue: context.state.lowGlucose,
                        targetGlucose: 90,
                        glucoseColorScheme: context.state.glucoseColorScheme,
                        offset: 20
                    )

                    let chartDate = additionalState.chartDate[index] ?? Date()

                    let pointMark = PointMark(
                        x: .value("Time", chartDate),
                        y: .value("Value", displayValue)
                    ).symbolSize(15)

                    pointMark.foregroundStyle(pointMarkColor)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { _ in
                    AxisGridLine(stroke: .init(lineWidth: 0.2, dash: [2, 3])).foregroundStyle(Color.white)
                    AxisValueLabel().foregroundStyle(.secondary).font(.footnote)
                }
            }
            .chartYScale(domain: additionalState.unit == "mg/dL" ? min ... max : min.asMmolL ... max.asMmolL)
            .chartXAxis {
                AxisMarks(position: .automatic) { _ in
                    AxisGridLine(stroke: .init(lineWidth: 0.2, dash: [2, 3])).foregroundStyle(Color.white)
                }
            }
        }
    }

    @ViewBuilder func content(context: ActivityViewContext<LiveActivityAttributes>) -> some View {
        let hasStaticColorScheme = context.state.glucoseColorScheme == "staticColor"
        // TODO: grab target from proper targets, do not hard code.
        let glucoseColor = getDynamicGlucoseColor(
            glucoseValue: Decimal(string: context.state.bg) ?? 100,
            highGlucoseColorValue: context.state.detailedViewState?.unit == "mg/dL" ? context.state.highGlucose : context.state
                .highGlucose.asMmolL,
            lowGlucoseColorValue: context.state.detailedViewState?.unit == "mg/dL" ? context.state.lowGlucose : context.state
                .lowGlucose.asMmolL,
            targetGlucose: context.state.detailedViewState?.unit == "mg/dL" ? 90 : 90.asMmolL,
            glucoseColorScheme: context.state.glucoseColorScheme,
            offset: context.state.detailedViewState?.unit == "mg/dL" ? 20 : 20.asMmolL
        )

        if let detailedViewState = context.state.detailedViewState {
            HStack(spacing: 12) {
                chart(context: context, additionalState: detailedViewState)
                    .frame(maxWidth: UIScreen.main.bounds.width / 1.8)
                VStack(alignment: .leading) {
                    Spacer()
                    bgLabel(context: context, additionalState: detailedViewState)
                    HStack {
                        changeLabel(context: context)
                        trendArrow(context: context, additionalState: detailedViewState)
                    }
                    mealLabel(context: context, additionalState: detailedViewState).padding(.bottom, 8)
                    updatedLabel(context: context).padding(.bottom, 10)
                }
            }
            .privacySensitive()
            .padding(.all, 14)
            .imageScale(.small)
            .foregroundColor(Color.white)
            .activityBackgroundTint(Color.black.opacity(0.8))
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
                        bgAndTrend(
                            context: context,
                            size: .expanded,
                            hasStaticColorScheme: hasStaticColorScheme,
                            glucoseColor: glucoseColor
                        ).0.font(.title)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 5) {
                            changeLabel(context: context).font(.title3)
                                .foregroundStyle(hasStaticColorScheme ? .primary : glucoseColor)
                            updatedLabel(context: context).font(.caption)
                                .foregroundStyle(
                                    hasStaticColorScheme ? .primary
                                        .opacity(0.7) : glucoseColor
                                )
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
        let glucoseValueForColor = context.state.bg
        let highGlucose = context.state.highGlucose
        let lowGlucose = context.state.lowGlucose

        let hasStaticColorScheme = context.state.glucoseColorScheme == "staticColor"
        // TODO: grab target from proper targets, do not hard code.
        let glucoseColor = getDynamicGlucoseColor(
            glucoseValue: Decimal(string: glucoseValueForColor) ?? 100,
            highGlucoseColorValue: context.state.detailedViewState?.unit == "mg/dL" ? highGlucose : highGlucose.asMmolL,
            lowGlucoseColorValue: context.state.detailedViewState?.unit == "mg/dL" ? lowGlucose : lowGlucose.asMmolL,
            targetGlucose: context.state.detailedViewState?.unit == "mg/dL" ? 90 : 90.asMmolL,
            glucoseColorScheme: context.state.glucoseColorScheme,
            offset: context.state.detailedViewState?.unit == "mg/dL" ? 20 : 20.asMmolL
        )

        return DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                bgAndTrend(
                    context: context,
                    size: .expanded,
                    hasStaticColorScheme: hasStaticColorScheme,
                    glucoseColor: glucoseColor
                ).0.font(.title2).padding(.leading, 5)
            }
            DynamicIslandExpandedRegion(.trailing) {
                changeLabel(context: context).font(.title2).padding(.trailing, 5)
                    .foregroundStyle(hasStaticColorScheme ? .primary : glucoseColor)
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
            bgAndTrend(context: context, size: .compact, hasStaticColorScheme: hasStaticColorScheme, glucoseColor: glucoseColor).0
                .padding(.leading, 4)
        } compactTrailing: {
            changeLabel(context: context).padding(.trailing, 4).foregroundStyle(hasStaticColorScheme ? .primary : glucoseColor)
        } minimal: {
            let (_label, characterCount) = bgAndTrend(
                context: context,
                size: .minimal,
                hasStaticColorScheme: hasStaticColorScheme,
                glucoseColor: glucoseColor
            )
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
        .keylineTint(hasStaticColorScheme ? Color.purple : glucoseColor)
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
            bg: 00.0.description,
            direction: "→",
            change: "+0.0",
            date: Date(),
            highGlucose: 180,
            lowGlucose: 70,
            glucoseColorScheme: "staticColor",
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
            highGlucose: 180,
            lowGlucose: 70,
            glucoseColorScheme: "staticColor",
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
            highGlucose: 180,
            lowGlucose: 70,
            glucoseColorScheme: "staticColor",
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
            highGlucose: 180,
            lowGlucose: 70,
            glucoseColorScheme: "staticColor",
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
            highGlucose: 180,
            lowGlucose: 70,
            glucoseColorScheme: "staticColor",
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
            highGlucose: 180,
            lowGlucose: 70,
            glucoseColorScheme: "staticColor",
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
