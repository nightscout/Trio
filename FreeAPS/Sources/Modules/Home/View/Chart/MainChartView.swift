import Charts
import CoreData
import SwiftUI

let screenSize: CGRect = UIScreen.main.bounds
let calendar = Calendar.current

struct MainChartView: View {
    var geo: GeometryProxy
    var units: GlucoseUnits
    var hours: Int
    var tempTargets: [TempTarget]
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
    @State var chartTempTargets: [ChartTempTarget] = []
    @State var startMarker =
        Date(timeIntervalSinceNow: TimeInterval(hours: -24))
    @State var endMarker = Date(timeIntervalSinceNow: TimeInterval(hours: 3))

    @State var selection: Date? = nil

    @State var mainChartHasInitialized = false

    let now = Date.now

    private let context = CoreDataStack.shared.persistentContainer.viewContext

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.calendar) var calendar

    var upperLimit: Decimal {
        units == .mgdL ? 400 : 22.2
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
        let range = selection.addingTimeInterval(-120) ... selection.addingTimeInterval(120)
        return findDetermination(in: range)
    }

    var selectedIOBValue: OrefDetermination? {
        guard let selection = selection else { return nil }
        let range = selection.addingTimeInterval(-120) ... selection.addingTimeInterval(120)
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
                            ZStack {
                                cobChart
                                iobChart
                            }

                        }.onChange(of: screenHours) {
                            scroller.scrollTo("MainChart", anchor: .trailing)
                        }
                        .onChange(of: state.glucoseFromPersistence.last?.glucose) {
                            scroller.scrollTo("MainChart", anchor: .trailing)
                            updateStartEndMarkers()
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
                                updateStartEndMarkers()
                                calculateTempBasalsInBackground()
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
                drawTempTargets()

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
                    units: state.units
                )

                CarbView(
                    glucoseData: state.glucoseFromPersistence,
                    units: state.units,
                    carbData: state.carbsFromPersistence,
                    fpuData: state.fpusFromPersistence,
                    minValue: state.minYAxisValue
                )

                OverrideView(
                    overrides: state.overrides,
                    overrideRunStored: state.overrideRunStored,
                    units: state.units,
                    viewContext: context
                )

                ForecastView(
                    preprocessedData: state.preprocessedData,
                    minForecast: state.minForecast,
                    maxForecast: state.maxForecast,
                    units: state.units,
                    maxValue: state.maxYAxisValue,
                    forecastDisplayType: state.forecastDisplayType
                )

                /// show glucose value when hovering over it
                if #available(iOS 17, *) {
                    if let selectedGlucose {
                        RuleMark(x: .value("Selection", selectedGlucose.date ?? now, unit: .minute))
                            .foregroundStyle(Color.tabBar)
                            .offset(yStart: 70)
                            .lineStyle(.init(lineWidth: 2))
                            .annotation(
                                position: .top,
                                alignment: .center,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                            ) {
                                selectionPopover
                            }

                        PointMark(
                            x: .value("Time", selectedGlucose.date ?? now, unit: .minute),
                            y: .value("Value", selectedGlucose.glucose)
                        )
                        .zIndex(-1)
                        .symbolSize(CGSize(width: 15, height: 15))
                        .foregroundStyle(
                            Decimal(selectedGlucose.glucose) > highGlucose ? Color.orange
                                .opacity(0.8) :
                                (
                                    Decimal(selectedGlucose.glucose) < lowGlucose ? Color.red.opacity(0.8) : Color.green
                                        .opacity(0.8)
                                )
                        )

                        PointMark(
                            x: .value("Time", selectedGlucose.date ?? now, unit: .minute),
                            y: .value("Value", selectedGlucose.glucose)
                        )
                        .zIndex(-1)
                        .symbolSize(CGSize(width: 6, height: 6))
                        .foregroundStyle(Color.primary)
                    }
                }
            }
            .id("MainChart")
            .onChange(of: state.insulinFromPersistence) {
                state.roundedTotalBolus = state.calculateTINS()
            }
            .onChange(of: tempTargets) {
                Task {
                    await calculateTempTargets()
                }
            }
            .frame(minHeight: geo.size.height * 0.28)
            .frame(width: fullWidth(viewWidth: screenSize.width))
            .chartXScale(domain: startMarker ... endMarker)
            .chartXAxis { mainChartXAxis }
            .chartYAxis { mainChartYAxis }
            .chartYAxis(.hidden)
            .backport.chartXSelection(value: $selection)
            .chartYScale(
                domain: units == .mgdL ? state.minYAxisValue ... state.maxYAxisValue : state.minYAxisValue
                    .asMmolL ... state.maxYAxisValue.asMmolL
            )
            .backport.chartForegroundStyleScale(state: state)
        }
    }

    @ViewBuilder var selectionPopover: some View {
        if let sgv = selectedGlucose?.glucose {
            VStack(alignment: .leading) {
                HStack {
                    Image(systemName: "clock")
                    Text(selectedGlucose?.date?.formatted(.dateTime.hour().minute(.twoDigits)) ?? "")
                        .font(.body).bold()
                }.font(.body).padding(.bottom, 5)

                // TODO: workaround for now: set low value to 55, to have dynamic color shades between 55 and user-set low (approx. 70); same for high glucose
                let hardCodedLow = Decimal(55)
                let hardCodedHigh = Decimal(220)
                let isDynamicColorScheme = glucoseColorScheme == .dynamicColor

                let glucoseColor = FreeAPS.getDynamicGlucoseColor(
                    glucoseValue: Decimal(sgv),
                    highGlucoseColorValue: isDynamicColorScheme ? hardCodedHigh : highGlucose,
                    lowGlucoseColorValue: isDynamicColorScheme ? hardCodedLow : lowGlucose,
                    targetGlucose: currentGlucoseTarget,
                    glucoseColorScheme: glucoseColorScheme
                )
                HStack {
                    Text(units == .mgdL ? Decimal(sgv).description : Decimal(sgv).formattedAsMmolL)
                        .bold()
                        + Text(" \(units.rawValue)")
                }.foregroundStyle(
                    Color(glucoseColor)
                ).font(.body)

                if let selectedIOBValue, let iob = selectedIOBValue.iob {
                    HStack {
                        Image(systemName: "syringe.fill").frame(width: 15)
                        Text(MainChartHelper.bolusFormatter.string(from: iob) ?? "")
                            .bold()
                            + Text(NSLocalizedString(" U", comment: "Insulin unit"))
                    }.foregroundStyle(Color.insulin).font(.body)
                }

                if let selectedCOBValue {
                    HStack {
                        Image(systemName: "fork.knife").frame(width: 15)
                        Text(MainChartHelper.carbsFormatter.string(from: selectedCOBValue.cob as NSNumber) ?? "")
                            .bold()
                            + Text(NSLocalizedString(" g", comment: "gram of carbs"))
                    }.foregroundStyle(Color.orange).font(.body)
                }
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.chart.opacity(0.85))
                    .shadow(color: Color.secondary, radius: 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary, lineWidth: 2)
                    )
            }
        }
    }
}

// MARK: - Rule Marks and Charts configurations

extension MainChartView {
    func drawCurrentTimeMarker() -> some ChartContent {
        RuleMark(
            x: .value(
                "",
                Date(timeIntervalSince1970: TimeInterval(NSDate().timeIntervalSince1970)),
                unit: .second
            )
        ).lineStyle(.init(lineWidth: 2, dash: [3])).foregroundStyle(Color(.systemGray2))
    }

    func drawStartRuleMark() -> some ChartContent {
        RuleMark(
            x: .value(
                "",
                startMarker,
                unit: .second
            )
        ).foregroundStyle(Color.clear)
    }

    func drawEndRuleMark() -> some ChartContent {
        RuleMark(
            x: .value(
                "",
                endMarker,
                unit: .second
            )
        ).foregroundStyle(Color.clear)
    }

    func basalChartPlotStyle(_ plotContent: ChartPlotContent) -> some View {
        plotContent
            .rotationEffect(.degrees(180))
            .scaleEffect(x: -1, y: 1)
    }

    var mainChartXAxis: some AxisContent {
        AxisMarks(values: .stride(by: .hour, count: screenHours > 6 ? (screenHours > 12 ? 4 : 2) : 1)) { _ in
            if displayXgridLines {
                AxisGridLine(stroke: .init(lineWidth: 0.5, dash: [2, 3]))
            } else {
                AxisGridLine(stroke: .init(lineWidth: 0, dash: [2, 3]))
            }
        }
    }

    var basalChartXAxis: some AxisContent {
        AxisMarks(values: .stride(by: .hour, count: screenHours > 6 ? (screenHours > 12 ? 4 : 2) : 1)) { _ in
            if displayXgridLines {
                AxisGridLine(stroke: .init(lineWidth: 0.5, dash: [2, 3]))
            } else {
                AxisGridLine(stroke: .init(lineWidth: 0, dash: [2, 3]))
            }
            AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .narrow)), anchor: .top)
                .font(.footnote).foregroundStyle(Color.primary)
        }
    }

    var mainChartYAxis: some AxisContent {
        AxisMarks(position: .trailing) { value in

            if displayYgridLines {
                AxisGridLine(stroke: .init(lineWidth: 0.5, dash: [2, 3]))
            } else {
                AxisGridLine(stroke: .init(lineWidth: 0, dash: [2, 3]))
            }

            if let glucoseValue = value.as(Double.self), glucoseValue > 0 {
                /// fix offset between the two charts...
                if units == .mmolL {
                    AxisTick(length: 7, stroke: .init(lineWidth: 7)).foregroundStyle(Color.clear)
                }
                AxisValueLabel().font(.footnote).foregroundStyle(Color.primary)
            }
        }
    }

    var cobChartYAxis: some AxisContent {
        AxisMarks(position: .trailing) { _ in
            if displayYgridLines {
                AxisGridLine(stroke: .init(lineWidth: 0.5, dash: [2, 3]))
            } else {
                AxisGridLine(stroke: .init(lineWidth: 0, dash: [2, 3]))
            }
        }
    }
}

// MARK: - Calculations and formatting

extension MainChartView {
    func fullWidth(viewWidth: CGFloat) -> CGFloat {
        viewWidth * CGFloat(hours) / CGFloat(min(max(screenHours, 2), 24))
    }

    // Update start and  end marker to fix scroll update problem with x axis
    func updateStartEndMarkers() {
        startMarker = Date(timeIntervalSince1970: TimeInterval(NSDate().timeIntervalSince1970 - 86400))

        let threeHourSinceNow = Date(timeIntervalSinceNow: TimeInterval(hours: 3))

        // min is 1.5h -> (1.5*1h = 1.5*(5*12*60))
        let dynamicFutureDateForCone = Date(timeIntervalSinceNow: TimeInterval(
            Int(1.5) * 5 * state
                .minCount * 60
        ))

        endMarker = state
            .forecastDisplayType == .lines ? threeHourSinceNow : dynamicFutureDateForCone <= threeHourSinceNow ?
            dynamicFutureDateForCone.addingTimeInterval(TimeInterval(minutes: 30)) : threeHourSinceNow
    }
}

extension Int16 {
    var minutes: TimeInterval {
        TimeInterval(self) * 60
    }
}
