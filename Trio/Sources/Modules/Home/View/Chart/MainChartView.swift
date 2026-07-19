import Charts
import CoreData
import SwiftUI

let screenSize: CGRect = UIScreen.main.bounds
let calendar = Calendar.current

struct MainChartView: View {
    var geo: GeometryProxy
    /// height allocated by the Home layout: the remainder after the fixed zones
    var chartHeight: CGFloat
    var units: GlucoseUnits
    var hours: Int
    var highGlucose: Decimal
    var lowGlucose: Decimal
    var currentGlucoseTarget: Decimal
    var glucoseColorScheme: GlucoseColorScheme
    var screenHours: Int16
    var displayXgridLines: Bool
    var displayYgridLines: Bool
    var thresholdLines: Bool
    var state: Home.StateModel

    @State var basalProfiles: [BasalProfile] = []
    @State var preparedTempBasals: [(start: Date, end: Date, rate: Double)] = []
    @State var selection: Date? = nil

    @State var mainChartHasInitialized = false

    let now = Date.now

    private let context = CoreDataStack.shared.persistentContainer.viewContext

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.calendar) var calendar

    var upperLimit: Decimal {
        units == .mgdL ? 400 : 22.2
    }

    // pane splits of the chart's allocation (old 0.05/0.28/0.12 screen-fraction
    // proportions); sums to 0.94 so pane spacing and axis labels fit the budget
    var basalHeight: CGFloat { chartHeight * 0.10 }
    var mainHeight: CGFloat { chartHeight * 0.60 }
    var cobIobHeight: CGFloat { chartHeight * 0.24 }

    /// drawn in the scrolling chart (not the static y-axis dummy) so the rules
    /// share the exact plot geometry of the glucose marks
    @ChartContentBuilder private var thresholdRuleMarks: some ChartContent {
        // dynamic color shade anchors: 55 low / 220 high
        let hardCodedLow = Decimal(55)
        let hardCodedHigh = Decimal(220)
        let isDynamicColorScheme = glucoseColorScheme == .dynamicColor

        if thresholdLines {
            let highColor = Trio.getDynamicGlucoseColor(
                glucoseValue: highGlucose,
                highGlucoseColorValue: isDynamicColorScheme ? hardCodedHigh : highGlucose,
                lowGlucoseColorValue: isDynamicColorScheme ? hardCodedLow : lowGlucose,
                targetGlucose: currentGlucoseTarget,
                glucoseColorScheme: glucoseColorScheme
            )
            let lowColor = Trio.getDynamicGlucoseColor(
                glucoseValue: lowGlucose,
                highGlucoseColorValue: isDynamicColorScheme ? hardCodedHigh : highGlucose,
                lowGlucoseColorValue: isDynamicColorScheme ? hardCodedLow : lowGlucose,
                targetGlucose: currentGlucoseTarget,
                glucoseColorScheme: glucoseColorScheme
            )

            RuleMark(y: .value("High", units == .mgdL ? highGlucose : highGlucose.asMmolL))
                .foregroundStyle(highColor)
                .lineStyle(.init(lineWidth: 1, dash: [5]))
            RuleMark(y: .value("Low", units == .mgdL ? lowGlucose : lowGlucose.asMmolL))
                .foregroundStyle(lowColor)
                .lineStyle(.init(lineWidth: 1, dash: [5]))
        }
    }

    private var selectedGlucose: GlucoseStored? {
        guard let selection = selection else { return nil }
        let range = selection.addingTimeInterval(-150) ... selection.addingTimeInterval(150)
        return state.glucoseFromPersistence.first { $0.date.map(range.contains) ?? false }
    }

    private func findDetermination(in range: ClosedRange<Date>) -> OrefDetermination? {
        state.enactedAndNonEnactedDeterminations.first {
            $0.deliverAt ?? now >= range.lowerBound && $0.deliverAt ?? now <= range.upperBound
        }
    }

    var selectedCOBValue: OrefDetermination? {
        guard let selection = selection else { return nil }
        let range = selection.addingTimeInterval(-150) ... selection.addingTimeInterval(150)
        return findDetermination(in: range)
    }

    var selectedIOBValue: OrefDetermination? {
        guard let selection = selection else { return nil }
        let range = selection.addingTimeInterval(-150) ... selection.addingTimeInterval(150)
        return findDetermination(in: range)
    }

    var body: some View {
        VStack {
            ZStack {
                VStack(spacing: 5) {
                    dummyBasalChart
                    staticYAxisChart
                    Spacer()
                    dummyCobChart
                }

                ScrollViewReader { scroller in
                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(spacing: 5) {
                            basalChart
                            mainChart
                            Spacer()
                            cobIobChart
                        }.onChange(of: screenHours) {
                            scroller.scrollTo("MainChart", anchor: .trailing)
                        }
                        .onChange(of: state.glucoseFromPersistence.last?.glucose) {
                            scroller.scrollTo("MainChart", anchor: .trailing)
                            state.updateStartEndMarkers()
                        }
                        .onChange(of: state.enactedAndNonEnactedDeterminations.first?.deliverAt) {
                            scroller.scrollTo("MainChart", anchor: .trailing)
                        }
                        .onChange(of: units) {
                            // TODO: - Refactor this to only update the Y Axis Scale
                            state.setupGlucoseArray()
                        }
                        .onAppear {
                            if !mainChartHasInitialized {
                                scroller.scrollTo("MainChart", anchor: .trailing)
                                state.updateStartEndMarkers()
                                calculateTempBasals()
                                mainChartHasInitialized = true
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Main Chart with selection Popover

extension MainChartView {
    private var mainChart: some View {
        VStack {
            Chart {
                drawStartRuleMark()
                drawEndRuleMark()
                drawCurrentTimeMarker()
                thresholdRuleMarks

                GlucoseTargetsView(
                    targetProfiles: state.targetProfiles
                )

                OverrideView(
                    state: state,
                    overrides: state.overrides,
                    overrideRunStored: state.overrideRunStored,
                    units: state.units,
                    viewContext: context
                )

                TempTargetView(
                    tempTargetStored: state.tempTargetStored,
                    tempTargetRunStored: state.tempTargetRunStored,
                    units: state.units,
                    viewContext: context
                )

                GlucoseChartView(
                    glucoseData: state.glucoseFromPersistence,
                    units: state.units,
                    highGlucose: state.highGlucose,
                    lowGlucose: state.lowGlucose,
                    currentGlucoseTarget: state.currentGlucoseTarget,
                    isSmoothingEnabled: state.isSmoothingEnabled,
                    glucoseColorScheme: state.glucoseColorScheme
                )

                InsulinView(
                    glucoseData: state.glucoseFromPersistence,
                    insulinData: state.insulinFromPersistence,
                    units: state.units,
                    bolusDisplayThreshold: state.bolusDisplayThreshold
                )

                CarbView(
                    glucoseData: state.glucoseFromPersistence,
                    units: state.units,
                    carbData: state.carbsFromPersistence,
                    fpuData: state.fpusFromPersistence,
                    minValue: units == .mgdL ? state.minYAxisValue : state.minYAxisValue
                        .asMmolL
                )

                ForecastView(
                    preprocessedData: state.preprocessedData,
                    minForecast: state.minForecast,
                    maxForecast: state.maxForecast,
                    units: state.units,
                    maxValue: state.maxYAxisValue,
                    forecastDisplayType: state.forecastDisplayType,
                    lastDeterminationDate: state.determinationsFromPersistence.first?.deliverAt ?? .distantPast
                )

                /// show glucose value when hovering over it
                if let selectedGlucose {
                    SelectionPopoverView(
                        selectedGlucose: selectedGlucose,
                        selectedIOBValue: selectedIOBValue,
                        selectedCOBValue: selectedCOBValue,
                        units: units,
                        highGlucose: highGlucose,
                        lowGlucose: lowGlucose,
                        currentGlucoseTarget: currentGlucoseTarget,
                        glucoseColorScheme: glucoseColorScheme,
                        isSmoothingEnabled: state.settingsManager.settings.smoothGlucose
                    )
                }
            }
            .id("MainChart")
            .frame(
                minHeight: mainHeight
            )
            .frame(width: fullWidth(viewWidth: screenSize.width))
            .chartXScale(domain: state.startMarker ... state.endMarker)
            .chartXAxis { mainChartXAxis }
            .chartYAxis { mainChartYAxis }
            .chartYAxis(.hidden)
            .chartXSelection(value: $selection)
            .chartYScale(
                domain: units == .mgdL ? state.minYAxisValue ... state.maxYAxisValue : state.minYAxisValue
                    .asMmolL ... state.maxYAxisValue.asMmolL
            )
            .chartLegend(.hidden)
            .chartForegroundStyleScale([
                "iob": Color.insulin,
                "uam": Color.uam,
                "zt": Color.zt,
                "cob": Color.orange
            ])
        }
    }
}
