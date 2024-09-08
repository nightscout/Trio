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
    @State private var mainChartHasInitialized = false

    private let now = Date.now

    private let context = CoreDataStack.shared.persistentContainer.viewContext

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.calendar) var calendar

    private var upperLimit: Decimal {
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

// MARK: - Components

extension MainChartView {
    /// empty chart that just shows the Y axis and Y grid lines. Created separately from `mainChart` to allow main chart to scroll horizontally while having a fixed Y axis
    private var staticYAxisChart: some View {
        Chart {
            /// high and low threshold lines
            if thresholdLines {
                RuleMark(y: .value("High", highGlucose)).foregroundStyle(Color.loopYellow)
                    .lineStyle(.init(lineWidth: 1, dash: [5]))
                RuleMark(y: .value("Low", lowGlucose)).foregroundStyle(Color.loopRed)
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
        .chartYScale(domain: units == .mgdL ? minValue ... maxValue : minValue.asMmolL ... maxValue.asMmolL)
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
                drawTempTargets()

                GlucoseChartView(
                    glucoseData: state.glucoseFromPersistence,
                    manualGlucoseData: state.manualGlucoseFromPersistence,
                    units: state.units,
                    highGlucose: state.highGlucose,
                    lowGlucose: state.lowGlucose,
                    smooth: state.smooth,
                    gradientStops: state.gradientStops
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
            .onChange(of: didAppearTrigger) { _ in
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
            .foregroundStyle(Color.purple.opacity(0.75)).lineStyle(.init(lineWidth: 8))
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

    private func fullWidth(viewWidth: CGFloat) -> CGFloat {
        viewWidth * CGFloat(hours) / CGFloat(min(max(screenHours, 2), 24))
    }

    /// calculations for temp target bar mark
    private func calculateTTs() async {
        // Perform calculations off the main thread
        let calculatedTTs = await Task.detached { () -> [ChartTempTarget] in
            var groupedPackages: [[TempTarget]] = []
            var currentPackage: [TempTarget] = []
            var calculatedTTs: [ChartTempTarget] = []

            for target in await tempTargets {
                if target.duration > 0 {
                    if !currentPackage.isEmpty {
                        groupedPackages.append(currentPackage)
                        currentPackage = []
                    }
                    currentPackage.append(target)
                } else if let lastNonZeroTempTarget = currentPackage.last(where: { $0.duration > 0 }) {
                    // Ensure this cancel target is within the valid time range
                    if target.createdAt >= lastNonZeroTempTarget.createdAt,
                       target.createdAt <= lastNonZeroTempTarget.createdAt
                       .addingTimeInterval(TimeInterval(lastNonZeroTempTarget.duration * 60))
                    {
                        currentPackage.append(target)
                    }
                }
            }

            // Append the last group, if any
            if !currentPackage.isEmpty {
                groupedPackages.append(currentPackage)
            }

            for package in groupedPackages {
                guard let firstNonZeroTarget = package.first(where: { $0.duration > 0 }) else { continue }

                var end = firstNonZeroTarget.createdAt.addingTimeInterval(TimeInterval(firstNonZeroTarget.duration * 60))

                let earliestCancelTarget = package.filter({ $0.duration == 0 }).min(by: { $0.createdAt < $1.createdAt })

                if let earliestCancelTarget = earliestCancelTarget {
                    end = min(earliestCancelTarget.createdAt, end)
                }

                if let targetTop = firstNonZeroTarget.targetTop {
                    let adjustedTarget = await units == .mgdL ? targetTop : targetTop.asMmolL
                    calculatedTTs
                        .append(ChartTempTarget(amount: adjustedTarget, start: firstNonZeroTarget.createdAt, end: end))
                }
            }

            return calculatedTTs
        }.value

        // Update chartTempTargets on the main thread
        await MainActor.run {
            self.chartTempTargets = calculatedTTs
        }
    }

    private func findRegularBasalPoints(
        timeBegin: TimeInterval,
        timeEnd: TimeInterval,
        autotuned: Bool
    ) async -> [BasalProfile] {
        guard timeBegin < timeEnd else { return [] }

        let beginDate = Date(timeIntervalSince1970: timeBegin)
        let startOfDay = Calendar.current.startOfDay(for: beginDate)
        let profile = autotuned ? autotunedBasalProfile : basalProfile
        var basalPoints: [BasalProfile] = []

        // Iterate over the next three days, multiplying the time intervals
        for dayOffset in 0 ..< 3 {
            let dayTimeOffset = TimeInterval(dayOffset * 24 * 60 * 60) // One Day in seconds
            for entry in profile {
                let basalTime = startOfDay.addingTimeInterval(entry.minutes.minutes.timeInterval + dayTimeOffset)
                let basalTimeInterval = basalTime.timeIntervalSince1970

                // Only append points within the timeBegin and timeEnd range
                if basalTimeInterval >= timeBegin, basalTimeInterval < timeEnd {
                    basalPoints.append(BasalProfile(
                        amount: Double(entry.rate),
                        isOverwritten: false,
                        startDate: basalTime
                    ))
                }
            }
        }

        return basalPoints
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
            .forecastDisplayType == .lines ? threeHourSinceNow : dynamicFutureDateForCone <= threeHourSinceNow ?
            dynamicFutureDateForCone.addingTimeInterval(TimeInterval(minutes: 30)) : threeHourSinceNow
    }

    private func calculateBasals() {
        Task {
            let dayAgoTime = Date().addingTimeInterval(-1.days.timeInterval).timeIntervalSince1970

            // Get Regular and Autotuned Basal parallel
            async let getRegularBasalPoints = findRegularBasalPoints(
                timeBegin: dayAgoTime,
                timeEnd: endMarker.timeIntervalSince1970,
                autotuned: false
            )

            async let getAutotunedBasalPoints = findRegularBasalPoints(
                timeBegin: dayAgoTime,
                timeEnd: endMarker.timeIntervalSince1970,
                autotuned: true
            )

            let (regularPoints, autotunedBasalPoints) = await (getRegularBasalPoints, getAutotunedBasalPoints)

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

            await MainActor.run {
                basalProfiles = basals
            }
        }
    }

    // MARK: - Chart formatting

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

    private var cobChartYAxis: some AxisContent {
        AxisMarks(position: .trailing) { _ in
            if displayYgridLines {
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
