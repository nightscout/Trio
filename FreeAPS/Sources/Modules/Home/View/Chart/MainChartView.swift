import Charts
import CoreData
import SwiftUI

let screenSize: CGRect = UIScreen.main.bounds
let calendar = Calendar.current

struct MainChartView: View {
    var geo: GeometryProxy
    @Binding var units: GlucoseUnits
    @Binding var hours: Int
    @Binding var tempTargets: [TempTarget]
    @Binding var highGlucose: Decimal
    @Binding var lowGlucose: Decimal
    @Binding var screenHours: Int16
    @Binding var displayXgridLines: Bool
    @Binding var displayYgridLines: Bool
    @Binding var thresholdLines: Bool

    @StateObject var state: Home.StateModel

    @State var basalProfiles: [BasalProfile] = []
    @State var chartTempTargets: [ChartTempTarget] = []
    @State var startMarker =
        Date(timeIntervalSinceNow: TimeInterval(hours: -24))
    @State var endMarker = Date(timeIntervalSinceNow: TimeInterval(hours: 3))
    @State var minValue: Decimal = 45
    @State var maxValue: Decimal = 270
    @State var selection: Date? = nil
    @State var minValueCobChart: Decimal = 0
    @State var maxValueCobChart: Decimal = 20
    @State var minValueIobChart: Decimal = 0
    @State var maxValueIobChart: Decimal = 5
    @State var mainChartHasInitialized = false

    let now = Date.now

    private let context = CoreDataStack.shared.persistentContainer.viewContext

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.calendar) var calendar

    var upperLimit: Decimal {
        units == .mgdL ? 400 : 22.2
    }

    private var selectedGlucose: GlucoseStored? {
        if let selection = selection {
            let lowerBound = selection.addingTimeInterval(-150)
            let upperBound = selection.addingTimeInterval(150)
            return state.glucoseFromPersistence.first { $0.date ?? now >= lowerBound && $0.date ?? now <= upperBound }
        } else {
            return nil
        }
    }

    var selectedCOBValue: OrefDetermination? {
        if let selection = selection {
            let lowerBound = selection.addingTimeInterval(-120)
            let upperBound = selection.addingTimeInterval(120)
            return state.enactedAndNonEnactedDeterminations.first {
                $0.deliverAt ?? now >= lowerBound && $0.deliverAt ?? now <= upperBound
            }
        } else {
            return nil
        }
    }

    var selectedIOBValue: OrefDetermination? {
        if let selection = selection {
            let lowerBound = selection.addingTimeInterval(-120)
            let upperBound = selection.addingTimeInterval(120)
            return state.enactedAndNonEnactedDeterminations.first {
                $0.deliverAt ?? now >= lowerBound && $0.deliverAt ?? now <= upperBound
            }
        } else {
            return nil
        }
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

                        }.onChange(of: screenHours) { _ in
                            scroller.scrollTo("MainChart", anchor: .trailing)
                        }
                        .onChange(of: state.glucoseFromPersistence.last?.glucose) { _ in
                            updateStartEndMarkers()
                            yAxisChartData()
                            scroller.scrollTo("MainChart", anchor: .trailing)
                        }
                        .onChange(of: state.enactedAndNonEnactedDeterminations.first?.deliverAt) { _ in
                            yAxisChartDataCobChart()
                            yAxisChartDataIobChart()
                            scroller.scrollTo("MainChart", anchor: .trailing)
                        }
                        .onChange(of: units) { _ in
                            yAxisChartData()
                            yAxisChartDataCobChart()
                            yAxisChartDataIobChart()
                        }
                        .onAppear {
                            if !mainChartHasInitialized {
                                updateStartEndMarkers()
                                yAxisChartData()
                                yAxisChartDataCobChart()
                                yAxisChartDataIobChart()
                                mainChartHasInitialized = true
                                scroller.scrollTo("MainChart", anchor: .trailing)
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
                    manualGlucoseData: state.manualGlucoseFromPersistence,
                    units: state.units,
                    highGlucose: state.highGlucose,
                    lowGlucose: state.lowGlucose,
                    isSmoothingEnabled: state.isSmoothingEnabled
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
                    minValue: minValue
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
                    maxValue: maxValue,
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
            .onChange(of: state.insulinFromPersistence) { _ in
                state.roundedTotalBolus = state.calculateTINS()
            }
            .onChange(of: tempTargets) { _ in
                Task {
                    await calculateTTs()
                }
            }
            .frame(minHeight: geo.size.height * 0.28)
            .frame(width: fullWidth(viewWidth: screenSize.width))
            .chartXScale(domain: startMarker ... endMarker)
            .chartXAxis { mainChartXAxis }
            .chartYAxis { mainChartYAxis }
            .chartYAxis(.hidden)
            .backport.chartXSelection(value: $selection)
            .chartYScale(domain: units == .mgdL ? minValue ... maxValue : minValue.asMmolL ... maxValue.asMmolL)
            .backport.chartForegroundStyleScale(state: state)
        }
    }

    @ViewBuilder var selectionPopover: some View {
        if let sgv = selectedGlucose?.glucose {
            let glucoseToShow = units == .mgdL ? Decimal(sgv) : Decimal(sgv).asMmolL
            VStack(alignment: .leading) {
                HStack {
                    Image(systemName: "clock")
                    Text(selectedGlucose?.date?.formatted(.dateTime.hour().minute(.twoDigits)) ?? "")
                        .font(.body).bold()
                }.font(.body).padding(.bottom, 5)

                HStack {
                    Text(units == .mgdL ? glucoseToShow.description : Decimal(sgv).formattedAsMmolL)
                        .bold()
                        + Text(" \(units.rawValue)")
                }.foregroundStyle(
                    glucoseToShow < lowGlucose ? Color
                        .red : (glucoseToShow > highGlucose ? Color.orange : Color.primary)
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

    private func yAxisChartData() {
        Task {
            let (minGlucose, maxGlucose, minForecast, maxForecast) = await Task
                .detached { () -> (Decimal?, Decimal?, Decimal?, Decimal?) in
                    let glucoseMapped = await state.glucoseFromPersistence.map { Decimal($0.glucose) }
                    let forecastValues = await state.preprocessedData.map { Decimal($0.forecastValue.value) }

                    // Calculate min and max values for glucose and forecast
                    return (glucoseMapped.min(), glucoseMapped.max(), forecastValues.min(), forecastValues.max())
                }.value

            // Ensure all values exist, otherwise set default values
            guard let minGlucose = minGlucose, let maxGlucose = maxGlucose,
                  let minForecast = minForecast, let maxForecast = maxForecast
            else {
                await updateChartBounds(minValue: 45 - 20, maxValue: 270 + 50)
                return
            }

            // Adjust max forecast to be no more than 100 over max glucose
            let adjustedMaxForecast = min(maxForecast, maxGlucose + 100)
            let minOverall = min(minGlucose, minForecast)
            let maxOverall = max(maxGlucose, adjustedMaxForecast)

            // Update the chart bounds on the main thread
            await updateChartBounds(minValue: minOverall - 50, maxValue: maxOverall + 80)
        }
    }

    @MainActor private func updateChartBounds(minValue: Decimal, maxValue: Decimal) async {
        self.minValue = minValue
        self.maxValue = maxValue
    }

    private func yAxisChartDataCobChart() {
        Task {
            let maxCob = await Task.detached { () -> Decimal? in
                let cobMapped = await state.enactedAndNonEnactedDeterminations.map { Decimal($0.cob) }
                return cobMapped.max()
            }.value

            // Ensure the result exists or set default values
            if let maxCob = maxCob {
                let calculatedMax = maxCob == 0 ? 20 : maxCob + 20
                await updateCobChartBounds(minValue: 0, maxValue: calculatedMax)
            } else {
                await updateCobChartBounds(minValue: 0, maxValue: 20)
            }
        }
    }

    @MainActor private func updateCobChartBounds(minValue: Decimal, maxValue: Decimal) async {
        minValueCobChart = minValue
        maxValueCobChart = maxValue
    }

    private func yAxisChartDataIobChart() {
        Task {
            let (minIob, maxIob) = await Task.detached { () -> (Decimal?, Decimal?) in
                let iobMapped = await state.enactedAndNonEnactedDeterminations.compactMap { $0.iob?.decimalValue }
                return (iobMapped.min(), iobMapped.max())
            }.value

            // Ensure min and max IOB values exist, or set defaults
            if let minIob = minIob, let maxIob = maxIob {
                let adjustedMin = minIob < 0 ? minIob - 2 : 0
                await updateIobChartBounds(minValue: adjustedMin, maxValue: maxIob + 2)
            } else {
                await updateIobChartBounds(minValue: 0, maxValue: 5)
            }
        }
    }

    @MainActor private func updateIobChartBounds(minValue: Decimal, maxValue: Decimal) async {
        minValueIobChart = minValue
        maxValueIobChart = maxValue
    }
}

extension Int16 {
    var minutes: TimeInterval {
        TimeInterval(self) * 60
    }
}
