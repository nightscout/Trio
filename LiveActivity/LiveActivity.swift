import ActivityKit
import Charts
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

extension Color {
    static let systemBackground = Color(UIColor.systemBackground)
}

struct LiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivityAttributes.self) { context in
            LiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LiveActivityExpandedLeadingView(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LiveActivityExpandedTrailingView(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    LiveActivityExpandedBottomView(context: context)
                }
                DynamicIslandExpandedRegion(.center) {
                    LiveActivityExpandedCenterView(context: context)
                }
            } compactLeading: {
                LiveActivityCompactLeadingView(context: context)
            } compactTrailing: {
                LiveActivityCompactTrailingView(context: context)
            } minimal: {
                LiveActivityMinimalView(context: context)
            }
        }
    }
}

struct LiveActivityView: View {
    @Environment(\.colorScheme) var colorScheme
    var context: ActivityViewContext<LiveActivityAttributes>

    var body: some View {
        if let detailedViewState = context.state.detailedViewState {
            VStack {
                LiveActivityChartView(context: context, additionalState: detailedViewState)
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.9)
                    .frame(height: 80)
                    .overlay(alignment: .topTrailing) {
                        if detailedViewState.isOverrideActive {
                            HStack {
                                Text("\(detailedViewState.overrideName)")
                                    .font(.footnote)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                            }
                            .padding(6)
                            .background {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.purple.opacity(colorScheme == .dark ? 0.6 : 0.8))
                            }
                        }
                    }

                HStack {
                    ForEach(context.state.itemOrder, id: \.self) { item in
                        switch item {
                        case "currentGlucose":
                            if context.state.showCurrentGlucose {
                                VStack {
                                    LiveActivityBGLabelView(context: context, additionalState: detailedViewState)
                                    HStack {
                                        LiveActivityGlucoseDeltaLabelView(context: context)
                                        if !context.isStale, let direction = context.state.direction {
                                            Text(direction).font(.headline)
                                        }
                                    }
                                }
                            }
                        case "iob":
                            if context.state.showIOB {
                                LiveActivityIOBLabelView(context: context, additionalState: detailedViewState)
                            }
                        case "cob":
                            if context.state.showCOB {
                                LiveActivityCOBLabelView(context: context, additionalState: detailedViewState)
                            }
                        case "updatedLabel":
                            if context.state.showUpdatedLabel {
                                LiveActivityUpdatedLabelView(context: context, isDetailedLayout: true)
                            }
                        default:
                            EmptyView()
                        }
                        Divider().foregroundStyle(.primary).fontWeight(.bold).frame(width: 10)
                    }
                }
            }
            .privacySensitive()
            .padding(.all, 14)
            .foregroundStyle(Color.primary)
            .activityBackgroundTint(colorScheme == .light ? Color.white.opacity(0.43) : Color.black.opacity(0.43))
        } else {
            HStack(spacing: 3) {
                LiveActivityBGAndTrendView(context: context, size: .expanded).font(.title)
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    LiveActivityGlucoseDeltaLabelView(context: context).font(.title3)
                    LiveActivityUpdatedLabelView(context: context, isDetailedLayout: false).font(.caption)
                        .foregroundStyle(.primary.opacity(0.7))
                }
            }
            .privacySensitive()
            .padding(.all, 15)
            .foregroundStyle(Color.primary)
            .activityBackgroundTint(colorScheme == .light ? Color.white.opacity(0.43) : Color.black.opacity(0.43))
        }
    }
}

// Separate the smaller sections into reusable views
struct LiveActivityBGAndTrendView: View {
    var context: ActivityViewContext<LiveActivityAttributes>
    fileprivate var size: Size

    var body: some View {
        let (view, _) = bgAndTrend(context: context, size: size)
        return view
    }
}

struct LiveActivityBGLabelView: View {
    var context: ActivityViewContext<LiveActivityAttributes>
    var additionalState: LiveActivityAttributes.ContentAdditionalState

    var body: some View {
        Text(context.state.bg)
            .fontWeight(.bold)
            .font(.title3)
            .strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))
    }
}

struct LiveActivityGlucoseDeltaLabelView: View {
    var context: ActivityViewContext<LiveActivityAttributes>

    var body: some View {
        if !context.state.change.isEmpty {
            Text(context.state.change).foregroundStyle(.primary).font(.subheadline)
                .strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))
        } else {
            Text("--")
        }
    }
}

struct LiveActivityIOBLabelView: View {
    var context: ActivityViewContext<LiveActivityAttributes>
    var additionalState: LiveActivityAttributes.ContentAdditionalState

    private var bolusFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.decimalSeparator = "."
        return formatter
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(
                    bolusFormatter.string(from: additionalState.iob as NSNumber) ?? "--"
                ).fontWeight(.bold).font(.title3).strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))
                Text("U").foregroundStyle(.primary).font(.headline).fontWeight(.bold)
            }
            Text("IOB").font(.subheadline).foregroundStyle(.primary)
        }
    }
}

struct LiveActivityCOBLabelView: View {
    var context: ActivityViewContext<LiveActivityAttributes>
    var additionalState: LiveActivityAttributes.ContentAdditionalState

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(
                    "\(additionalState.cob)"
                ).fontWeight(.bold).font(.title3).strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))
                Text("g").foregroundStyle(.primary).font(.headline).fontWeight(.bold)
            }
            Text("COB").font(.subheadline).foregroundStyle(.primary)
        }
    }
}

struct LiveActivityUpdatedLabelView: View {
    var context: ActivityViewContext<LiveActivityAttributes>
    var isDetailedLayout: Bool

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        if isDetailedLayout {
            let dateText = Text("\(dateFormatter.string(from: context.state.date))").font(.title3)
                .foregroundStyle(.primary)

            VStack {
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
        } else {
            let dateText = Text("\(dateFormatter.string(from: context.state.date))").font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Text("Updated:").font(.subheadline).foregroundStyle(.secondary)

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
            }
        }
    }
}

struct LiveActivityChartView: View {
    var context: ActivityViewContext<LiveActivityAttributes>
    var additionalState: LiveActivityAttributes.ContentAdditionalState

    var body: some View {
        // Determine scale
        let minValue = min(additionalState.chart.min() ?? 39, 39) as Decimal
        let maxValue = max(additionalState.chart.max() ?? 300, 300) as Decimal

        let yAxisRuleMarkMin = additionalState.unit == "mg/dL" ? additionalState.lowGlucose : additionalState.lowGlucose
            .asMmolL
        let yAxisRuleMarkMax = additionalState.unit == "mg/dL" ? additionalState.highGlucose : additionalState.highGlucose
            .asMmolL
        let target = additionalState.unit == "mg/dL" ? additionalState.target : additionalState.target.asMmolL

        let calendar = Calendar.current
        let now = Date()

        let startDate = calendar.date(byAdding: .hour, value: -6, to: now) ?? now
        let endDate = calendar.date(byAdding: .hour, value: 2, to: now) ?? now

        Chart {
            RuleMark(y: .value("Low", yAxisRuleMarkMin))
                .lineStyle(.init(lineWidth: 0.5, dash: [5]))
            RuleMark(y: .value("High", yAxisRuleMarkMax))
                .lineStyle(.init(lineWidth: 0.5, dash: [5]))
            RuleMark(y: .value("Target", target)).foregroundStyle(.green.gradient).lineStyle(.init(lineWidth: 1))

            if context.state.detailedViewState?.isOverrideActive == true {
                drawActiveOverrides()
            }

            drawChart(yAxisRuleMarkMin: yAxisRuleMarkMin, yAxisRuleMarkMax: yAxisRuleMarkMax)
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
        .chartXScale(domain: startDate ... endDate)
        .chartXAxis {
            AxisMarks(position: .automatic) { _ in
                AxisGridLine(stroke: .init(lineWidth: 0.2, dash: [2, 3])).foregroundStyle(Color.white)
            }
        }
    }

    private func drawActiveOverrides() -> some ChartContent {
        let start: Date = context.state.detailedViewState?.overrideDate ?? .distantPast

        let duration = context.state.detailedViewState?.overrideDuration ?? 0
        let durationAsTimeInterval = TimeInterval((duration as NSDecimalNumber).doubleValue * 60) // return seconds

        let end: Date = start.addingTimeInterval(durationAsTimeInterval)
        let target = context.state.detailedViewState?.overrideTarget ?? 0

        return RuleMark(
            xStart: .value("Start", start, unit: .second),
            xEnd: .value("End", end, unit: .second),
            y: .value("Value", target)
        )
        .foregroundStyle(Color.purple.opacity(0.6))
        .lineStyle(.init(lineWidth: 8))
    }

    private func drawChart(yAxisRuleMarkMin: Decimal, yAxisRuleMarkMax: Decimal) -> some ChartContent {
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
}

// Expanded, minimal, compact view components
struct LiveActivityExpandedLeadingView: View {
    var context: ActivityViewContext<LiveActivityAttributes>

    var body: some View {
        LiveActivityBGAndTrendView(context: context, size: .expanded).font(.title2).padding(.leading, 5)
    }
}

struct LiveActivityExpandedTrailingView: View {
    var context: ActivityViewContext<LiveActivityAttributes>

    var body: some View {
        LiveActivityGlucoseDeltaLabelView(context: context).font(.title2).padding(.trailing, 5)
    }
}

struct LiveActivityExpandedBottomView: View {
    var context: ActivityViewContext<LiveActivityAttributes>

    var body: some View {
        if context.state.isInitialState {
            Text("Live Activity Expired. Open Trio to Refresh")
        } else if let detailedViewState = context.state.detailedViewState {
            LiveActivityChartView(context: context, additionalState: detailedViewState)
        }
    }
}

struct LiveActivityExpandedCenterView: View {
    var context: ActivityViewContext<LiveActivityAttributes>

    var body: some View {
        LiveActivityUpdatedLabelView(context: context, isDetailedLayout: false).font(.caption).foregroundStyle(Color.secondary)
    }
}

struct LiveActivityCompactLeadingView: View {
    var context: ActivityViewContext<LiveActivityAttributes>

    var body: some View {
        LiveActivityBGAndTrendView(context: context, size: .compact).padding(.leading, 4)
    }
}

struct LiveActivityCompactTrailingView: View {
    var context: ActivityViewContext<LiveActivityAttributes>

    var body: some View {
        LiveActivityGlucoseDeltaLabelView(context: context).padding(.trailing, 4)
    }
}

struct LiveActivityMinimalView: View {
    var context: ActivityViewContext<LiveActivityAttributes>

    var body: some View {
        let (label, characterCount) = bgAndTrend(context: context, size: .minimal)
        let adjustedLabel = label.padding(.leading, 7).padding(.trailing, 3)

        if characterCount < 4 {
            adjustedLabel
        } else if characterCount < 5 {
            adjustedLabel.fontWidth(.condensed)
        } else {
            adjustedLabel.fontWidth(.compressed)
        }
    }
}

// Helper function for bgAndTrend logic
private func bgAndTrend(context: ActivityViewContext<LiveActivityAttributes>, size _: Size) -> (some View, Int) {
    var characters = 0
    let bgText = context.state.bg
    characters += bgText.count

    var directionText: String?
    if let direction = context.state.direction {
        directionText = direction
        characters += directionText!.count
    }

    let stack = HStack {
        Text(bgText)
        if let direction = directionText {
            Text(direction)
        }
    }

    return (stack, characters)
}
