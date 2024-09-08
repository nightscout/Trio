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
    private let dateFormatter: DateFormatter = {
        var f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private var bolusFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
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
        HStack(spacing: -5) {
            if !context.state.change.isEmpty {
                Text(context.state.change).foregroundStyle(.primary).font(.subheadline)
                    .strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))
            } else {
                Text("--")
            }
        }
    }

    @ViewBuilder func cobLabel(
        context: ActivityViewContext<LiveActivityAttributes>,
        additionalState: LiveActivityAttributes.ContentAdditionalState
    ) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(
                    carbsFormatter.string(from: additionalState.cob as NSNumber) ?? "--"
                ).fontWeight(.bold).font(.title3).strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))
                Text(NSLocalizedString("g", comment: "grams of carbs")).foregroundStyle(.primary).font(.headline)
                    .fontWeight(.bold)
            }

            Text("COB").font(.subheadline).foregroundStyle(.primary)
        }
    }

    @ViewBuilder func iobLabel(
        context: ActivityViewContext<LiveActivityAttributes>,
        additionalState: LiveActivityAttributes.ContentAdditionalState
    ) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(
                    bolusFormatter.string(from: additionalState.iob as NSNumber) ?? "--"
                ).font(.title3).fontWeight(.bold).strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))
                Text(NSLocalizedString("U", comment: "Unit in number of units delivered (keep the space character!)"))
                    .foregroundStyle(.primary).font(.headline).fontWeight(.bold)
            }

            Text("IOB").font(.subheadline).foregroundStyle(.primary)
        }
    }

    @ViewBuilder func mealLabel(
        context: ActivityViewContext<LiveActivityAttributes>,
        additionalState: LiveActivityAttributes.ContentAdditionalState
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 0, content: {
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
            VStack(alignment: .trailing, spacing: 0, content: {
                HStack {
                    Text(
                        carbsFormatter.string(from: additionalState.cob as NSNumber) ?? "--"
                    ).fontWeight(.bold).font(.title3).strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))
                    Text(NSLocalizedString(" g", comment: "grams of carbs")).foregroundStyle(.primary).font(.headline)
                }
                HStack {
                    Text(
                        bolusFormatter.string(from: additionalState.iob as NSNumber) ?? "--"
                    ).font(.title3).fontWeight(.bold).strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))
                    Text(NSLocalizedString(" U", comment: "Unit in number of units delivered (keep the space character!)"))
                        .foregroundStyle(.primary).font(.headline)
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

    @ViewBuilder private func updatedLabel(context: ActivityViewContext<LiveActivityAttributes>) -> some View {
        VStack {
            let dateText = Text("\(dateFormatter.string(from: context.state.date))").font(.title3).foregroundStyle(.primary)

            if context.isStale {
                if #available(iOSApplicationExtension 17.0, *) {
                    dateText.bold().foregroundStyle(.red)
                } else {
                    dateText.bold().foregroundColor(.red)
                }
            } else {
                if #available(iOSApplicationExtension 17.0, *) {
                    dateText.bold().foregroundStyle(.primary)
                } else {
                    dateText.bold().foregroundColor(.primary)
                }
            }

            Text("Updated").font(.subheadline).foregroundStyle(.primary)
        }
    }

    @ViewBuilder private func bgLabel(
        context: ActivityViewContext<LiveActivityAttributes>,
        additionalState _: LiveActivityAttributes.ContentAdditionalState
    ) -> some View {
        HStack(alignment: .center) {
            Text(context.state.bg)
                .fontWeight(.bold)
                .font(.title3)
                .strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))
        }
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
            if size == .compact {
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
        .foregroundStyle(context.isStale ? Color.primary.opacity(0.5) : Color.primary)

        return (stack, characters)
    }

    @ViewBuilder func chart(
        context: ActivityViewContext<LiveActivityAttributes>,
        additionalState: LiveActivityAttributes.ContentAdditionalState
    ) -> some View {
        if context.isStale {
            Text("No data available")
        } else {
            // Determine scale
            let minValue = min(additionalState.chart.min() ?? 45, 40) - 20
            let maxValue = max(additionalState.chart.max() ?? 270, 300) + 50

            let yAxisRuleMarkMin = additionalState.unit == "mg/dL" ? additionalState.lowGlucose : additionalState.lowGlucose
                .asMmolL
            let yAxisRuleMarkMax = additionalState.unit == "mg/dL" ? additionalState.highGlucose : additionalState.highGlucose
                .asMmolL
            let target = additionalState.unit == "mg/dL" ? additionalState.target : additionalState.target.asMmolL

            Chart {
                RuleMark(y: .value("Low", yAxisRuleMarkMin))
                    .lineStyle(.init(lineWidth: 0.5, dash: [5]))
                RuleMark(y: .value("High", yAxisRuleMarkMax))
                    .lineStyle(.init(lineWidth: 0.5, dash: [5]))
                RuleMark(y: .value("Target", target)).foregroundStyle(.green.gradient).lineStyle(.init(lineWidth: 1))

                ForEach(additionalState.chart.indices, id: \.self) { index in
                    let currentValue = additionalState.chart[index]
                    let displayValue = additionalState.unit == "mg/dL" ? currentValue : currentValue.asMmolL
                    let chartDate = additionalState.chartDate[index] ?? Date()
                    let pointMark = PointMark(
                        x: .value("Time", chartDate),
                        y: .value("Value", displayValue)
                    ).symbolSize(15)

                    if displayValue > yAxisRuleMarkMax {
                        pointMark.foregroundStyle(Color.orange.gradient)
                    } else if displayValue < yAxisRuleMarkMin {
                        pointMark.foregroundStyle(Color.red.gradient)
                    } else {
                        pointMark.foregroundStyle(Color.green.gradient)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { _ in
                    AxisGridLine(stroke: .init(lineWidth: 0.2, dash: [2, 3])).foregroundStyle(Color.white)
                    AxisValueLabel().foregroundStyle(.primary).font(.footnote)
                }
            }
            .chartYScale(domain: additionalState.unit == "mg/dL" ? minValue ... maxValue : minValue.asMmolL ... maxValue.asMmolL)
            .chartYAxis(.hidden)
            .chartPlotStyle { plotContent in
                plotContent
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.clear)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .chartXAxis {
                AxisMarks(position: .automatic) { _ in
                    AxisGridLine(stroke: .init(lineWidth: 0.2, dash: [2, 3])).foregroundStyle(Color.white)
                }
            }
        }
    }

    @ViewBuilder func content(context: ActivityViewContext<LiveActivityAttributes>) -> some View {
        if let detailedViewState = context.state.detailedViewState {
            VStack(content: {
                chart(context: context, additionalState: detailedViewState)
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.9)
                    .frame(height: 80)

                HStack {
                    ForEach(context.state.itemOrder, id: \.self) { item in
                        switch item {
                        case "currentGlucose":
                            if context.state.showCurrentGlucose {
                                VStack {
                                    bgLabel(context: context, additionalState: detailedViewState)
                                    HStack {
                                        changeLabel(context: context)
                                        if !context.isStale, let direction = context.state.direction {
                                            Text(direction).font(.headline)
                                        }
                                    }
                                }
                            }
                        case "iob":
                            if context.state.showIOB {
                                iobLabel(context: context, additionalState: detailedViewState)
                            }
                        case "cob":
                            if context.state.showCOB {
                                cobLabel(context: context, additionalState: detailedViewState)
                            }
                        case "updatedLabel":
                            if context.state.showUpdatedLabel {
                                updatedLabel(context: context)
                            }
                        default:
                            EmptyView()
                        }
                        Divider().foregroundStyle(.primary).fontWeight(.bold).frame(width: 10)
                    }
                }
            })
                .privacySensitive()
                .padding(.all, 14)
                .imageScale(.small)
                .foregroundStyle(Color.primary)
                .activityBackgroundTint(Color.clear)
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
            .activityBackgroundTint(Color.black.opacity(0.4))
        }
    }

    func dynamicIsland(context: ActivityViewContext<LiveActivityAttributes>) -> DynamicIsland {
        DynamicIsland {
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
            showCOB: true,
            showIOB: true,
            showCurrentGlucose: true,
            showUpdatedLabel: true,
            itemOrder: ["currentGlucose", "iob", "cob", "updatedLabel"],
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
            showCOB: true,
            showIOB: true,
            showCurrentGlucose: true,
            showUpdatedLabel: true,
            itemOrder: ["currentGlucose", "iob", "cob", "updatedLabel"],
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
            showCOB: true,
            showIOB: true,
            showCurrentGlucose: true,
            showUpdatedLabel: true,
            itemOrder: ["currentGlucose", "iob", "cob", "updatedLabel"],
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
            showCOB: true,
            showIOB: true,
            showCurrentGlucose: true,
            showUpdatedLabel: true,
            itemOrder: ["currentGlucose", "iob", "cob", "updatedLabel"],
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
            showCOB: true,
            showIOB: true,
            showCurrentGlucose: true,
            showUpdatedLabel: true,
            itemOrder: ["currentGlucose", "iob", "cob", "updatedLabel"],
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
            showCOB: true,
            showIOB: true,
            showCurrentGlucose: true,
            showUpdatedLabel: true,
            itemOrder: ["currentGlucose", "iob", "cob", "updatedLabel"],
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
