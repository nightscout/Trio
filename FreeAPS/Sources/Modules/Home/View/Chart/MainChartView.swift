import Charts
import CoreData
import SwiftUI

let screenSize: CGRect = UIScreen.main.bounds
let calendar = Calendar.current

private struct BasalProfile: Hashable {
    let amount: Double
    var isOverwritten: Bool
    let startDate: Date
    let endDate: Date?
    init(amount: Double, isOverwritten: Bool, startDate: Date, endDate: Date? = nil) {
        self.amount = amount
        self.isOverwritten = isOverwritten
        self.startDate = startDate
        self.endDate = endDate
    }
}

private struct ChartTempTarget: Hashable {
    let amount: Decimal
    let start: Date
    let end: Date
}

struct MainChartView: View {
    private enum Config {
        static let bolusSize: CGFloat = 5
        static let bolusScale: CGFloat = 1
        static let carbsSize: CGFloat = 5
        static let carbsScale: CGFloat = 0.3
        static let fpuSize: CGFloat = 10
        static let maxGlucose = 270
        static let minGlucose = 45
    }

    var geo: GeometryProxy
    @Binding var units: GlucoseUnits
    @Binding var announcement: [Announcement]
    @Binding var hours: Int
    @Binding var maxBasal: Decimal
    @Binding var autotunedBasalProfile: [BasalProfileEntry]
    @Binding var basalProfile: [BasalProfileEntry]
    @Binding var tempTargets: [TempTarget]
    @Binding var smooth: Bool
    @Binding var highGlucose: Decimal
    @Binding var lowGlucose: Decimal
    @Binding var screenHours: Int16
    @Binding var displayXgridLines: Bool
    @Binding var displayYgridLines: Bool
    @Binding var thresholdLines: Bool
    @Binding var isTempTargetActive: Bool

    @StateObject var state: Home.StateModel

    @State var didAppearTrigger = false
    @State private var basalProfiles: [BasalProfile] = []
    @State private var chartTempTargets: [ChartTempTarget] = []
    @State private var count: Decimal = 1
    @State private var startMarker =
        Date(timeIntervalSinceNow: TimeInterval(hours: -24))
    @State private var endMarker = Date(timeIntervalSinceNow: TimeInterval(hours: 3))
    @State private var minValue: Decimal = 45
    @State private var maxValue: Decimal = 270
    @State private var selection: Date? = nil
    @State private var minValueCobChart: Decimal = 0
    @State private var maxValueCobChart: Decimal = 20
    @State private var minValueIobChart: Decimal = 0
    @State private var maxValueIobChart: Decimal = 5

    private let now = Date.now

    private let context = CoreDataStack.shared.persistentContainer.viewContext

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.calendar) var calendar

    private var bolusFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumIntegerDigits = 0
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

    private var conversionFactor: Decimal {
        units == .mmolL ? 0.0555 : 1
    }

    private var upperLimit: Decimal {
        units == .mgdL ? 400 : 22.2
    }

    private var defaultBolusPosition: Int {
        units == .mgdL ? 120 : 7
    }

    private var bolusOffset: Decimal {
        units == .mgdL ? 30 : 1.66
    }

    private var selectedGlucose: GlucoseStored? {
        if let selection = selection {
            let lowerBound = selection.addingTimeInterval(-120)
            let upperBound = selection.addingTimeInterval(120)
            return state.glucoseFromPersistence.first { $0.date ?? now >= lowerBound && $0.date ?? now <= upperBound }
        } else {
            return nil
        }
    }

    private var selectedCOBValue: OrefDetermination? {
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

    private var selectedIOBValue: OrefDetermination? {
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
                            updateStartEndMarkers()
                            yAxisChartData()
                            yAxisChartDataCobChart()
                            yAxisChartDataIobChart()
                            scroller.scrollTo("MainChart", anchor: .trailing)
                        }
                        .onChange(of: state.glucoseFromPersistence.last?.glucose) { _ in
                            updateStartEndMarkers()
                            yAxisChartData()
                            scroller.scrollTo("MainChart", anchor: .trailing)
                        }
                        .onChange(of: state.enactedAndNonEnactedDeterminations.first?.deliverAt) { _ in
                            updateStartEndMarkers()
                            yAxisChartDataCobChart()
                            yAxisChartDataIobChart()
                            scroller.scrollTo("MainChart", anchor: .trailing)
                        }
                        .onChange(of: state.tempBasals) { _ in
                            updateStartEndMarkers()
                            scroller.scrollTo("MainChart", anchor: .trailing)
                        }
                        .onChange(of: units) { _ in
                            yAxisChartData()
                        }
                        .onAppear {
                            updateStartEndMarkers()
                            yAxisChartData()
                            yAxisChartDataCobChart()
                            yAxisChartDataIobChart()
                            scroller.scrollTo("MainChart", anchor: .trailing)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Components

struct Backport<Content: View> {
    let content: Content
}

extension View {
    var backport: Backport<Self> { Backport(content: self) }
}

extension Backport {
    @ViewBuilder func chartXSelection(value: Binding<Date?>) -> some View {
        if #available(iOS 17, *) {
            content.chartXSelection(value: value)
        } else {
            content
        }
    }

    @ViewBuilder func chartForegroundStyleScale(state: any StateModel) -> some View {
        if (state as? Bolus.StateModel)?.displayForecastsAsLines == true ||
            (state as? Home.StateModel)?.displayForecastsAsLines == true
        {
            let modifiedContent = content
                .chartForegroundStyleScale([
                    "iob": .blue,
                    "uam": Color.uam,
                    "zt": Color.zt,
                    "cob": .orange
                ])

            if state is Home.StateModel {
                modifiedContent
                    .chartLegend(.hidden)
            } else {
                modifiedContent
            }
        } else {
            content
        }
    }
}

extension MainChartView {
    /// empty chart that just shows the Y axis and Y grid lines. Created separately from `mainChart` to allow main chart to scroll horizontally while having a fixed Y axis
    private var staticYAxisChart: some View {
        Chart {
            /// high and low threshold lines
            if thresholdLines {
                RuleMark(y: .value("High", highGlucose * conversionFactor)).foregroundStyle(Color.loopYellow)
                    .lineStyle(.init(lineWidth: 1, dash: [5]))
                RuleMark(y: .value("Low", lowGlucose * conversionFactor)).foregroundStyle(Color.loopRed)
                    .lineStyle(.init(lineWidth: 1, dash: [5]))
            }
        }
        .id("DummyMainChart")
        .frame(minHeight: geo.size.height * 0.28)
        .frame(width: screenSize.width - 10)
        .chartXAxis { mainChartXAxis }
        .chartXScale(domain: startMarker ... endMarker)
        .chartXAxis(.hidden)
        .chartYAxis { mainChartYAxis }
        .chartYScale(domain: minValue ... maxValue)
        .chartLegend(.hidden)
    }

    private var dummyBasalChart: some View {
        Chart {}
            .id("DummyBasalChart")
            .frame(minHeight: geo.size.height * 0.05)
            .frame(width: screenSize.width - 10)
            .chartXAxis { basalChartXAxis }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
    }

    private var dummyCobChart: some View {
        Chart {
            drawCOB(dummy: true)
        }
        .id("DummyCobChart")
        .frame(minHeight: geo.size.height * 0.12)
        .frame(width: screenSize.width - 10)
        .chartXScale(domain: startMarker ... endMarker)
        .chartXAxis { basalChartXAxis }
        .chartXAxis(.hidden)
        .chartYAxis { cobChartYAxis }
        .chartYAxis(.hidden)
        .chartYScale(domain: minValueCobChart ... maxValueCobChart)
        .chartLegend(.hidden)
    }

    private var mainChart: some View {
        VStack {
            Chart {
                drawStartRuleMark()
                drawEndRuleMark()
                drawCurrentTimeMarker()
                drawFpus()
                drawBoluses()
                drawTempTargets()
                drawActiveOverrides()
                drawOverrideRunStored()
                drawGlucose(dummy: false)
                drawManualGlucose()
                drawCarbs()

                if state.displayForecastsAsLines {
                    drawForecastsLines()
                } else {
                    drawForecastsCone()
                }

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
                calculateTTs()
            }
            .onChange(of: didAppearTrigger) { _ in
                calculateTTs()
            }
            .frame(minHeight: geo.size.height * 0.28)
            .frame(width: fullWidth(viewWidth: screenSize.width))
            .chartXScale(domain: startMarker ... endMarker)
            .chartXAxis { mainChartXAxis }
            .chartYAxis { mainChartYAxis }
            .chartYAxis(.hidden)
            .backport.chartXSelection(value: $selection)
            .chartYScale(domain: minValue ... maxValue)
            .backport.chartForegroundStyleScale(state: state)
        }
    }

    @ViewBuilder var selectionPopover: some View {
        if let sgv = selectedGlucose?.glucose {
            let glucoseToShow = Decimal(sgv) * conversionFactor
            VStack(alignment: .leading) {
                HStack {
                    Image(systemName: "clock")
                    Text(selectedGlucose?.date?.formatted(.dateTime.hour().minute(.twoDigits)) ?? "")
                        .font(.body).bold()
                }.font(.body).padding(.bottom, 5)

                HStack {
                    Text(glucoseToShow.formatted(.number.precision(units == .mmolL ? .fractionLength(1) : .fractionLength(0))))
                        .bold()
                        + Text(" \(units.rawValue)")
                }.foregroundStyle(
                    Decimal(sgv) < lowGlucose ? Color
                        .red : (Decimal(sgv) > highGlucose ? Color.orange : Color.primary)
                ).font(.body)

                if let selectedIOBValue, let iob = selectedIOBValue.iob {
                    HStack {
                        Image(systemName: "syringe.fill").frame(width: 15)
                        Text(bolusFormatter.string(from: iob) ?? "")
                            .bold()
                            + Text(NSLocalizedString(" U", comment: "Insulin unit"))
                    }.foregroundStyle(Color.insulin).font(.body)
                }

                if let selectedCOBValue {
                    HStack {
                        Image(systemName: "fork.knife").frame(width: 15)
                        Text(carbsFormatter.string(from: selectedCOBValue.cob as NSNumber) ?? "")
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

    private var basalChart: some View {
        VStack {
            Chart {
                drawStartRuleMark()
                drawEndRuleMark()
                drawCurrentTimeMarker()
                drawTempBasals(dummy: false)
                drawBasalProfile()
                drawSuspensions()
            }.onChange(of: state.tempBasals) { _ in
                calculateBasals()
            }
            .onChange(of: maxBasal) { _ in
                calculateBasals()
            }
            .onChange(of: autotunedBasalProfile) { _ in
                calculateBasals()
            }
            .onChange(of: didAppearTrigger) { _ in
                calculateBasals()
            }.onChange(of: basalProfile) { _ in
                calculateBasals()
            }
            .frame(minHeight: geo.size.height * 0.05)
            .frame(width: fullWidth(viewWidth: screenSize.width))
            .chartXScale(domain: startMarker ... endMarker)
            .chartXAxis { basalChartXAxis }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartPlotStyle { basalChartPlotStyle($0) }
        }
    }

    private var iobChart: some View {
        VStack {
            Chart {
                drawIOB()

                if #available(iOS 17, *) {
                    if let selectedIOBValue {
                        PointMark(
                            x: .value("Time", selectedIOBValue.deliverAt ?? now, unit: .minute),
                            y: .value("Value", Int(truncating: selectedIOBValue.iob ?? 0))
                        )
                        .symbolSize(CGSize(width: 15, height: 15))
                        .foregroundStyle(Color.darkerBlue.opacity(0.8))

                        PointMark(
                            x: .value("Time", selectedIOBValue.deliverAt ?? now, unit: .minute),
                            y: .value("Value", Int(truncating: selectedIOBValue.iob ?? 0))
                        )
                        .symbolSize(CGSize(width: 6, height: 6))
                        .foregroundStyle(Color.primary)
                    }
                }
            }
            .frame(minHeight: geo.size.height * 0.12)
            .frame(width: fullWidth(viewWidth: screenSize.width))
            .chartXScale(domain: startMarker ... endMarker)
            .backport.chartXSelection(value: $selection)
            .chartXAxis { basalChartXAxis }
            .chartYAxis { cobChartYAxis }
            .chartYScale(domain: minValueIobChart ... maxValueIobChart)
            .chartYAxis(.hidden)
        }
    }

    private var cobChart: some View {
        Chart {
            drawCurrentTimeMarker()
            drawCOB(dummy: false)

            if #available(iOS 17, *) {
                if let selectedCOBValue {
                    PointMark(
                        x: .value("Time", selectedCOBValue.deliverAt ?? now, unit: .minute),
                        y: .value("Value", selectedCOBValue.cob)
                    )
                    .symbolSize(CGSize(width: 15, height: 15))
                    .foregroundStyle(Color.orange.opacity(0.8))

                    PointMark(
                        x: .value("Time", selectedCOBValue.deliverAt ?? now, unit: .minute),
                        y: .value("Value", selectedCOBValue.cob)
                    )
                    .symbolSize(CGSize(width: 6, height: 6))
                    .foregroundStyle(Color.primary)
                }
            }
        }
        .frame(minHeight: geo.size.height * 0.12)
        .frame(width: fullWidth(viewWidth: screenSize.width))
        .chartXScale(domain: startMarker ... endMarker)
        .backport.chartXSelection(value: $selection)
        .chartXAxis { basalChartXAxis }
        .chartYAxis { cobChartYAxis }
        .chartYScale(domain: minValueCobChart ... maxValueCobChart)
    }
}

// MARK: - Calculations

extension MainChartView {
    private func drawBoluses() -> some ChartContent {
        ForEach(state.insulinFromPersistence) { insulin in
            let amount = insulin.bolus?.amount ?? 0 as NSDecimalNumber
            let bolusDate = insulin.timestamp ?? Date()

            if amount != 0, let glucose = timeToNearestGlucose(time: bolusDate.timeIntervalSince1970)?.glucose {
                let yPosition = (Decimal(glucose) * conversionFactor) + bolusOffset
                let size = (Config.bolusSize + CGFloat(truncating: amount) * Config.bolusScale) * 1.8

                PointMark(
                    x: .value("Time", bolusDate, unit: .second),
                    y: .value("Value", yPosition)
                )
                .symbol {
                    Image(systemName: "arrowtriangle.down.fill").font(.system(size: size)).foregroundStyle(Color.insulin)
                }
                .annotation(position: .top) {
                    Text(bolusFormatter.string(from: amount) ?? "")
                        .font(.caption2)
                        .foregroundStyle(Color.insulin)
                }
            }
        }
    }

    private func drawCarbs() -> some ChartContent {
        /// carbs
        ForEach(state.carbsFromPersistence) { carb in
            let carbAmount = carb.carbs
            let carbDate = carb.date ?? Date()

            if let glucose = timeToNearestGlucose(time: carbDate.timeIntervalSince1970)?.glucose {
                let yPosition = (Decimal(glucose) * conversionFactor) - bolusOffset
                let size = (Config.carbsSize + CGFloat(carbAmount) * Config.carbsScale)
                let limitedSize = size > 30 ? 30 : size

                PointMark(
                    x: .value("Time", carbDate, unit: .second),
                    y: .value("Value", yPosition)
                )
                .symbol {
                    Image(systemName: "arrowtriangle.down.fill").font(.system(size: limitedSize)).foregroundStyle(Color.orange)
                        .rotationEffect(.degrees(180))
                }
                .annotation(position: .bottom) {
                    Text(carbsFormatter.string(from: carbAmount as NSNumber)!).font(.caption2)
                        .foregroundStyle(Color.orange)
                }
            }
        }
    }

    private func drawFpus() -> some ChartContent {
        /// fpus
        ForEach(state.fpusFromPersistence, id: \.id) { fpu in
            let fpuAmount = fpu.carbs
            let size = (Config.fpuSize + CGFloat(fpuAmount) * Config.carbsScale) * 1.8
            let yPosition = minValue

            PointMark(
                x: .value("Time", fpu.date ?? Date(), unit: .second),
                y: .value("Value", yPosition)
            )
            .symbolSize(size)
            .foregroundStyle(Color.brown)
        }
    }

    private var stops: [Gradient.Stop] {
        let low = Double(lowGlucose)
        let high = Double(highGlucose)

        let glucoseValues = state.glucoseFromPersistence.map { Decimal($0.glucose) * conversionFactor }

        let minimum = glucoseValues.min() ?? 0.0
        let maximum = glucoseValues.max() ?? 0.0

        // Calculate positions for gradient
        let lowPosition = (low - Double(truncating: minimum as NSNumber)) /
            (Double(truncating: maximum as NSNumber) - Double(truncating: minimum as NSNumber))
        let highPosition = (high - Double(truncating: minimum as NSNumber)) /
            (Double(truncating: maximum as NSNumber) - Double(truncating: minimum as NSNumber))

        return [
            Gradient.Stop(color: .red, location: 0.0),
            Gradient.Stop(color: .red, location: lowPosition), // draw red gradient til lowGlucose
            Gradient.Stop(color: .green, location: lowPosition + 0.0001), // draw green above lowGlucose til highGlucose
            Gradient.Stop(color: .green, location: highPosition),
            Gradient.Stop(color: .orange, location: highPosition + 0.0001), // draw orange above highGlucose
            Gradient.Stop(color: .orange, location: 1.0)
        ]
    }

    private func drawGlucose(dummy _: Bool) -> some ChartContent {
        /// glucose point mark
        /// filtering for high and low bounds in settings
        ForEach(state.glucoseFromPersistence) { item in
            if smooth {
                LineMark(x: .value("Time", item.date ?? Date()), y: .value("Value", Decimal(item.glucose) * conversionFactor))
                    .foregroundStyle(
                        .linearGradient(stops: stops, startPoint: .bottom, endPoint: .top)
                    )
                    .symbol(.circle)
            } else {
                if item.glucose > Int(highGlucose) {
                    PointMark(
                        x: .value("Time", item.date ?? Date(), unit: .second),
                        y: .value("Value", Decimal(item.glucose) * conversionFactor)
                    ).foregroundStyle(Color.orange.gradient).symbolSize(20)
                } else if item.glucose < Int(lowGlucose) {
                    PointMark(
                        x: .value("Time", item.date ?? Date(), unit: .second),
                        y: .value("Value", Decimal(item.glucose) * conversionFactor)
                    ).foregroundStyle(Color.red.gradient).symbolSize(20)
                } else {
                    PointMark(
                        x: .value("Time", item.date ?? Date(), unit: .second),
                        y: .value("Value", Decimal(item.glucose) * conversionFactor)
                    ).foregroundStyle(Color.green.gradient).symbolSize(20)
                }
            }
        }
    }

    private func timeForIndex(_ index: Int32) -> Date {
        let currentTime = Date()
        let timeInterval = TimeInterval(index * 300)
        return currentTime.addingTimeInterval(timeInterval)
    }

    private func drawForecastsCone() -> some ChartContent {
        // Draw AreaMark for the forecast bounds
        ForEach(0 ..< max(state.minForecast.count, state.maxForecast.count), id: \.self) { index in
            if index < state.minForecast.count, index < state.maxForecast.count {
                let yMinValue = units == .mgdL ? Decimal(state.minForecast[index]) : Decimal(state.minForecast[index]).asMmolL
                let yMaxValue = units == .mgdL ? Decimal(state.maxForecast[index]) : Decimal(state.maxForecast[index]).asMmolL
                let xValue = timeForIndex(Int32(index))

                if xValue <= Date(timeIntervalSinceNow: TimeInterval(hours: 2.5)) {
                    AreaMark(
                        x: .value("Time", xValue),
                        // maxValue is already parsed to user units, no need to parse
                        yStart: .value("Min Value", yMinValue <= maxValue ? yMinValue : maxValue),
                        yEnd: .value("Max Value", yMaxValue <= maxValue ? yMaxValue : maxValue)
                    )
                    .foregroundStyle(Color.blue.opacity(0.5))
                    .interpolationMethod(.catmullRom)
                }
            }
        }
    }

    private func drawForecastsLines() -> some ChartContent {
        ForEach(state.preprocessedData, id: \.id) { tuple in
            let forecastValue = tuple.forecastValue
            let forecast = tuple.forecast
            let valueAsDecimal = Decimal(forecastValue.value)
            let displayValue = units == .mmolL ? valueAsDecimal.asMmolL : valueAsDecimal
            let xValue = timeForIndex(forecastValue.index)

            if xValue <= Date(timeIntervalSinceNow: TimeInterval(hours: 2.5)) {
                LineMark(
                    x: .value("Time", xValue),
                    y: .value("Value", displayValue)
                )
                .foregroundStyle(by: .value("Predictions", forecast.type ?? ""))
            }
        }
    }

    private func drawCurrentTimeMarker() -> some ChartContent {
        RuleMark(
            x: .value(
                "",
                Date(timeIntervalSince1970: TimeInterval(NSDate().timeIntervalSince1970)),
                unit: .second
            )
        ).lineStyle(.init(lineWidth: 2, dash: [3])).foregroundStyle(Color(.systemGray2))
    }

    private func drawStartRuleMark() -> some ChartContent {
        RuleMark(
            x: .value(
                "",
                startMarker,
                unit: .second
            )
        ).foregroundStyle(Color.clear)
    }

    private func drawEndRuleMark() -> some ChartContent {
        RuleMark(
            x: .value(
                "",
                endMarker,
                unit: .second
            )
        ).foregroundStyle(Color.clear)
    }

    private func drawTempTargets() -> some ChartContent {
        /// temp targets
        ForEach(chartTempTargets, id: \.self) { target in
            let targetLimited = min(max(target.amount, 0), upperLimit)

            RuleMark(
                xStart: .value("Start", target.start),
                xEnd: .value("End", target.end),
                y: .value("Value", targetLimited)
            )
            .foregroundStyle(Color.purple.opacity(0.5)).lineStyle(.init(lineWidth: 8))
        }
    }

    private func drawActiveOverrides() -> some ChartContent {
        ForEach(state.overrides) { override in
            let start: Date = override.date ?? .distantPast
            let duration = state.calculateDuration(override: override)
            let end: Date = start.addingTimeInterval(duration)
            let target = state.calculateTarget(override: override)

            RuleMark(
                xStart: .value("Start", start, unit: .second),
                xEnd: .value("End", end, unit: .second),
                y: .value("Value", target)
            )
            .foregroundStyle(Color.purple.opacity(0.6))
            .lineStyle(.init(lineWidth: 8))
//            .annotation(position: .overlay, spacing: 0) {
//                if let name = override.name {
//                    Text("\(name)").foregroundStyle(.secondary).font(.footnote)
//                }
//            }
        }
    }

    private func drawOverrideRunStored() -> some ChartContent {
        ForEach(state.overrideRunStored) { overrideRunStored in
            let start: Date = overrideRunStored.startDate ?? .distantPast
            let end: Date = overrideRunStored.endDate ?? Date()
            let target = overrideRunStored.target?.decimalValue ?? 100
            RuleMark(
                xStart: .value("Start", start, unit: .second),
                xEnd: .value("End", end, unit: .second),
                y: .value("Value", target)
            )
            .foregroundStyle(Color.purple.opacity(0.4))
            .lineStyle(.init(lineWidth: 8))
//            .annotation(position: .bottom, spacing: 0) {
//                if let name = overrideRunStored.override?.name {
//                    Text("\(name)").foregroundStyle(.secondary).font(.footnote)
//                }
//            }
        }
    }

    private func drawManualGlucose() -> some ChartContent {
        /// manual glucose mark
        ForEach(state.manualGlucoseFromPersistence) { item in
            let manualGlucose = item.glucose
            PointMark(
                x: .value("Time", item.date ?? Date(), unit: .second),
                y: .value("Value", Decimal(manualGlucose) * conversionFactor)
            )
            .symbol {
                Image(systemName: "drop.fill").font(.system(size: 10)).symbolRenderingMode(.monochrome)
                    .foregroundStyle(.red)
            }
        }
    }

    private func drawSuspensions() -> some ChartContent {
        let suspensions = state.suspensions
        return ForEach(suspensions) { suspension in
            let now = Date()

            if let type = suspension.type, type == EventType.pumpSuspend.rawValue, let suspensionStart = suspension.timestamp {
                let suspensionEnd = min(
                    (
                        suspensions
                            .first(where: {
                                $0.timestamp ?? now > suspensionStart && $0.type == EventType.pumpResume.rawValue })?
                            .timestamp
                    ) ?? now,
                    now
                )

                let basalProfileDuringSuspension = basalProfiles.first(where: { $0.startDate <= suspensionStart })
                let suspensionMarkHeight = basalProfileDuringSuspension?.amount ?? 1

                RectangleMark(
                    xStart: .value("start", suspensionStart),
                    xEnd: .value("end", suspensionEnd),
                    yStart: .value("suspend-start", 0),
                    yEnd: .value("suspend-end", suspensionMarkHeight)
                )
                .foregroundStyle(Color.loopGray.opacity(colorScheme == .dark ? 0.3 : 0.8))
            }
        }
    }

    private func drawIOB() -> some ChartContent {
        ForEach(state.enactedAndNonEnactedDeterminations) { iob in
            let rawAmount = iob.iob?.doubleValue ?? 0
            let amount: Double = rawAmount > 0 ? rawAmount : rawAmount * 2 // weigh negative iob with factor 2
            let date: Date = iob.deliverAt ?? Date()

            LineMark(x: .value("Time", date), y: .value("Amount", amount))
                .foregroundStyle(Color.darkerBlue)
            AreaMark(x: .value("Time", date), y: .value("Amount", amount))
                .foregroundStyle(
                    LinearGradient(
                        gradient: Gradient(
                            colors: [
                                Color.darkerBlue.opacity(0.8),
                                Color.darkerBlue.opacity(0.01)
                            ]
                        ),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }

    private func drawCOB(dummy: Bool) -> some ChartContent {
        ForEach(state.enactedAndNonEnactedDeterminations) { cob in
            let amount = Int(cob.cob)
            let date: Date = cob.deliverAt ?? Date()

            if dummy {
                LineMark(x: .value("Time", date), y: .value("Value", amount))
                    .foregroundStyle(Color.clear)
                AreaMark(x: .value("Time", date), y: .value("Value", amount)).foregroundStyle(
                    Color.clear
                )
            } else {
                LineMark(x: .value("Time", date), y: .value("Value", amount))
                    .foregroundStyle(Color.orange.gradient)
                AreaMark(x: .value("Time", date), y: .value("Value", amount)).foregroundStyle(
                    LinearGradient(
                        gradient: Gradient(
                            colors: [
                                Color.orange.opacity(0.8),
                                Color.orange.opacity(0.01)
                            ]
                        ),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
    }

    private func prepareTempBasals() -> [(start: Date, end: Date, rate: Double)] {
        let now = Date()
        let tempBasals = state.tempBasals

        return tempBasals.compactMap { temp -> (start: Date, end: Date, rate: Double)? in
            let duration = temp.tempBasal?.duration ?? 0
            let timestamp = temp.timestamp ?? Date()
            let end = min(timestamp + duration.minutes, now)
            let isInsulinSuspended = state.suspensions.contains { $0.timestamp ?? now >= timestamp && $0.timestamp ?? now <= end }

            let rate = Double(truncating: temp.tempBasal?.rate ?? Decimal.zero as NSDecimalNumber) * (isInsulinSuspended ? 0 : 1)

            // Check if there's a subsequent temp basal to determine the end time
            guard let nextTemp = state.tempBasals.first(where: { $0.timestamp ?? .distantPast > timestamp }) else {
                return (timestamp, end, rate)
            }
            return (timestamp, nextTemp.timestamp ?? Date(), rate) // end defaults to current time
        }
    }

    private func drawTempBasals(dummy: Bool) -> some ChartContent {
        ForEach(prepareTempBasals(), id: \.rate) { basal in
            if dummy {
                RectangleMark(
                    xStart: .value("start", basal.start),
                    xEnd: .value("end", basal.end),
                    yStart: .value("rate-start", 0),
                    yEnd: .value("rate-end", basal.rate)
                ).foregroundStyle(Color.clear)

                LineMark(x: .value("Start Date", basal.start), y: .value("Amount", basal.rate))
                    .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.clear)

                LineMark(x: .value("End Date", basal.end), y: .value("Amount", basal.rate))
                    .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.clear)
            } else {
                RectangleMark(
                    xStart: .value("start", basal.start),
                    xEnd: .value("end", basal.end),
                    yStart: .value("rate-start", 0),
                    yEnd: .value("rate-end", basal.rate)
                ).foregroundStyle(
                    LinearGradient(
                        gradient: Gradient(
                            colors: [
                                Color.insulin.opacity(0.6),
                                Color.insulin.opacity(0.1)
                            ]
                        ),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(x: .value("Start Date", basal.start), y: .value("Amount", basal.rate))
                    .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.insulin)

                LineMark(x: .value("End Date", basal.end), y: .value("Amount", basal.rate))
                    .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.insulin)
            }
        }
    }

    private func drawBasalProfile() -> some ChartContent {
        /// dashed profile line
        ForEach(basalProfiles, id: \.self) { profile in
            LineMark(
                x: .value("Start Date", profile.startDate),
                y: .value("Amount", profile.amount),
                series: .value("profile", "profile")
            ).lineStyle(.init(lineWidth: 2, dash: [2, 4])).foregroundStyle(Color.insulin)
            LineMark(
                x: .value("End Date", profile.endDate ?? endMarker),
                y: .value("Amount", profile.amount),
                series: .value("profile", "profile")
            ).lineStyle(.init(lineWidth: 2.5, dash: [2, 4])).foregroundStyle(Color.insulin)
        }
    }

    /// calculates the glucose value thats the nearest to parameter 'time'
    private func timeToNearestGlucose(time: TimeInterval) -> GlucoseStored? {
        guard !state.glucoseFromPersistence.isEmpty else {
            return nil
        }

        // sort by date
        let sortedGlucose = state.glucoseFromPersistence
            .sorted { $0.date?.timeIntervalSince1970 ?? 0 < $1.date?.timeIntervalSince1970 ?? 0 }

        var low = 0
        var high = sortedGlucose.count - 1
        var closestGlucose: GlucoseStored?

        // binary search to find next glucose
        while low <= high {
            let mid = low + (high - low) / 2
            let midTime = sortedGlucose[mid].date?.timeIntervalSince1970 ?? 0

            if midTime == time {
                return sortedGlucose[mid]
            } else if midTime < time {
                low = mid + 1
            } else {
                high = mid - 1
            }

            // update if necessary
            if closestGlucose == nil || abs(midTime - time) < abs(closestGlucose!.date?.timeIntervalSince1970 ?? 0 - time) {
                closestGlucose = sortedGlucose[mid]
            }
        }

        return closestGlucose
    }

    private func fullWidth(viewWidth: CGFloat) -> CGFloat {
        viewWidth * CGFloat(hours) / CGFloat(min(max(screenHours, 2), 24))
    }

    /// calculations for temp target bar mark
    private func calculateTTs() {
        var groupedPackages: [[TempTarget]] = []
        var currentPackage: [TempTarget] = []
        var calculatedTTs: [ChartTempTarget] = []

        for target in tempTargets {
            if target.duration > 0 {
                if !currentPackage.isEmpty {
                    groupedPackages.append(currentPackage)
                    currentPackage = []
                }
                currentPackage.append(target)
            } else {
                if let lastNonZeroTempTarget = currentPackage.last(where: { $0.duration > 0 }) {
                    if target.createdAt >= lastNonZeroTempTarget.createdAt,
                       target.createdAt <= lastNonZeroTempTarget.createdAt
                       .addingTimeInterval(TimeInterval(lastNonZeroTempTarget.duration * 60))
                    {
                        currentPackage.append(target)
                    }
                }
            }
        }

        // appends last package, if exists
        if !currentPackage.isEmpty {
            groupedPackages.append(currentPackage)
        }

        for package in groupedPackages {
            guard let firstNonZeroTarget = package.first(where: { $0.duration > 0 }) else {
                continue
            }

            var end = firstNonZeroTarget.createdAt.addingTimeInterval(TimeInterval(firstNonZeroTarget.duration * 60))

            let earliestCancelTarget = package.filter({ $0.duration == 0 }).min(by: { $0.createdAt < $1.createdAt })

            if let earliestCancelTarget = earliestCancelTarget {
                end = min(earliestCancelTarget.createdAt, end)
            }

            let now = Date()
            isTempTargetActive = firstNonZeroTarget.createdAt <= now && now <= end

            if firstNonZeroTarget.targetTop != nil {
                calculatedTTs
                    .append(ChartTempTarget(
                        amount: (firstNonZeroTarget.targetTop ?? 0) * conversionFactor,
                        start: firstNonZeroTarget.createdAt,
                        end: end
                    ))
            }
        }

        chartTempTargets = calculatedTTs
    }

    private func findRegularBasalPoints(
        timeBegin: TimeInterval,
        timeEnd: TimeInterval,
        autotuned: Bool
    ) -> [BasalProfile] {
        guard timeBegin < timeEnd else {
            return []
        }
        let beginDate = Date(timeIntervalSince1970: timeBegin)
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: beginDate)

        let profile = autotuned ? autotunedBasalProfile : basalProfile

        let basalNormalized = profile.map {
            (
                time: startOfDay.addingTimeInterval($0.minutes.minutes.timeInterval).timeIntervalSince1970,
                rate: $0.rate
            )
        } + profile.map {
            (
                time: startOfDay.addingTimeInterval($0.minutes.minutes.timeInterval + 1.days.timeInterval)
                    .timeIntervalSince1970,
                rate: $0.rate
            )
        } + profile.map {
            (
                time: startOfDay.addingTimeInterval($0.minutes.minutes.timeInterval + 2.days.timeInterval)
                    .timeIntervalSince1970,
                rate: $0.rate
            )
        }

        let basalTruncatedPoints = basalNormalized.windows(ofCount: 2)
            .compactMap { window -> BasalProfile? in
                let window = Array(window)
                if window[0].time < timeBegin, window[1].time < timeBegin {
                    return nil
                }

                if window[0].time < timeBegin, window[1].time >= timeBegin {
                    let startDate = Date(timeIntervalSince1970: timeBegin)
                    let rate = window[0].rate
                    return BasalProfile(amount: Double(rate), isOverwritten: false, startDate: startDate)
                }

                if window[0].time >= timeBegin, window[0].time < timeEnd {
                    let startDate = Date(timeIntervalSince1970: window[0].time)
                    let rate = window[0].rate
                    return BasalProfile(amount: Double(rate), isOverwritten: false, startDate: startDate)
                }

                return nil
            }

        return basalTruncatedPoints
    }

    /// update start and  end marker to fix scroll update problem with x axis
    private func updateStartEndMarkers() {
        startMarker = Date(timeIntervalSince1970: TimeInterval(NSDate().timeIntervalSince1970 - 86400))

        let threeHourSinceNow = Date(timeIntervalSinceNow: TimeInterval(hours: 3))

        // min is 1.5h -> (1.5*1h = 1.5*(5*12*60))
        let dynamicFutureDateForCone = Date(timeIntervalSinceNow: TimeInterval(
            Int(1.5) * 5 * state
                .minCount * 60
        ))

        endMarker = state
            .displayForecastsAsLines ? threeHourSinceNow : dynamicFutureDateForCone <= threeHourSinceNow ?
            dynamicFutureDateForCone.addingTimeInterval(TimeInterval(minutes: 30)) : threeHourSinceNow
    }

    private func calculateBasals() {
        let dayAgoTime = Date().addingTimeInterval(-1.days.timeInterval).timeIntervalSince1970
        let regularPoints = findRegularBasalPoints(
            timeBegin: dayAgoTime,
            timeEnd: endMarker.timeIntervalSince1970,
            autotuned: false
        )

        let autotunedBasalPoints = findRegularBasalPoints(
            timeBegin: dayAgoTime,
            timeEnd: endMarker.timeIntervalSince1970,
            autotuned: true
        )
        var totalBasal = regularPoints + autotunedBasalPoints
        totalBasal.sort {
            $0.startDate.timeIntervalSince1970 < $1.startDate.timeIntervalSince1970
        }
        var basals: [BasalProfile] = []
        totalBasal.indices.forEach { index in
            basals.append(BasalProfile(
                amount: totalBasal[index].amount,
                isOverwritten: totalBasal[index].isOverwritten,
                startDate: totalBasal[index].startDate,
                endDate: totalBasal.count > index + 1 ? totalBasal[index + 1].startDate : endMarker
            ))
        }
        basalProfiles = basals
    }

    // MARK: - Chart formatting

    private func yAxisChartData() {
        let glucoseMapped = state.glucoseFromPersistence.map { Decimal($0.glucose) }
        let forecastValues = state.preprocessedData.map { Decimal($0.forecastValue.value) }

        guard let minGlucose = glucoseMapped.min(), let maxGlucose = glucoseMapped.max(),
              let minForecast = forecastValues.min(), let maxForecast = forecastValues.max()
        else {
            // default values
            minValue = 45 * conversionFactor - 20 * conversionFactor
            maxValue = 270 * conversionFactor + 50 * conversionFactor
            return
        }

        // Ensure maxForecast is not more than 100 over maxGlucose
        let adjustedMaxForecast = min(maxForecast, maxGlucose + 100)

        let minOverall = min(minGlucose, minForecast)
        let maxOverall = max(maxGlucose, adjustedMaxForecast)

        minValue = minOverall * conversionFactor - 50 * conversionFactor
        maxValue = maxOverall * conversionFactor + 80 * conversionFactor
    }

    private func yAxisChartDataCobChart() {
        let cobMapped = state.enactedAndNonEnactedDeterminations.map { Decimal($0.cob) }
        guard let maxCob = cobMapped.max() else {
            // default values
            minValueCobChart = 0
            maxValueCobChart = 20
            return
        }
        maxValueCobChart = maxCob == 0 ? 20 : maxCob +
            20 // 2 is added to the max of iob and to keep the 1:10 ratio we add 20 here
    }

    private func yAxisChartDataIobChart() {
        let iobMapped = state.enactedAndNonEnactedDeterminations.compactMap { $0.iob?.decimalValue }
        guard let minIob = iobMapped.min(), let maxIob = iobMapped.max() else {
            // default values
            minValueIobChart = 0
            maxValueIobChart = 5
            return
        }
        minValueIobChart = minIob // we need to set this here because IOB can also be negative
        minValueCobChart = minIob < 0 ? minIob - 2 :
            0 // if there is negative IOB the COB-X-Axis should still align with the IOB-X-Axis; 2 is only subtracted to make the charts align
        maxValueIobChart = maxIob + 2
    }

    private func basalChartPlotStyle(_ plotContent: ChartPlotContent) -> some View {
        plotContent
            .rotationEffect(.degrees(180))
            .scaleEffect(x: -1, y: 1)
    }

    private var mainChartXAxis: some AxisContent {
        AxisMarks(values: .stride(by: .hour, count: screenHours > 6 ? (screenHours > 12 ? 4 : 2) : 1)) { _ in
            if displayXgridLines {
                AxisGridLine(stroke: .init(lineWidth: 0.5, dash: [2, 3]))
            } else {
                AxisGridLine(stroke: .init(lineWidth: 0, dash: [2, 3]))
            }
        }
    }

    private var basalChartXAxis: some AxisContent {
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

    private var mainChartYAxis: some AxisContent {
        AxisMarks(position: .trailing) { value in

            if displayXgridLines {
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

    private var cobChartYAxis: some AxisContent {
        AxisMarks(position: .trailing) { _ in
            if displayXgridLines {
                AxisGridLine(stroke: .init(lineWidth: 0.5, dash: [2, 3]))
            } else {
                AxisGridLine(stroke: .init(lineWidth: 0, dash: [2, 3]))
            }
        }
    }
}

struct LegendItem: View {
    var color: Color
    var label: String

    var body: some View {
        Group {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(color)
        }
    }
}

extension Int16 {
    var minutes: TimeInterval {
        TimeInterval(self) * 60
    }
}
