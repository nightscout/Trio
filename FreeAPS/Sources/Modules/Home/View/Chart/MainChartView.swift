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
    @State private var startMarker = Date(timeIntervalSince1970: TimeInterval(NSDate().timeIntervalSince1970 - 86400))
    @State private var endMarker = Date(timeIntervalSince1970: TimeInterval(NSDate().timeIntervalSince1970 + 10800))
    @State private var minValue: Decimal = 45
    @State private var maxValue: Decimal = 270
    @State private var selection: Date? = nil

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

    var body: some View {
        VStack {
            ZStack {
                VStack {
                    staticYAxisChart
                    dummyBasalChart
                }

                ScrollViewReader { scroller in
                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(spacing: 0) {
                            mainChart
                            basalChart
                        }.onChange(of: screenHours) { _ in
                            updateStartEndMarkers()
                            yAxisChartData()
                            scroller.scrollTo("MainChart", anchor: .trailing)
                        }
                        .onChange(of: state.glucoseFromPersistence.last?.glucose) { _ in
                            updateStartEndMarkers()
                            yAxisChartData()
                            scroller.scrollTo("MainChart", anchor: .trailing)
                        }
                        .onChange(of: state.determinationsFromPersistence.last?.deliverAt) { _ in
                            updateStartEndMarkers()
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
                            scroller.scrollTo("MainChart", anchor: .trailing)
                        }
                    }
                }
            }
            legendPanel.padding(.top, 8)
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
        .frame(minHeight: UIScreen.main.bounds.height * 0.2)
        .frame(width: screenSize.width - 10)
        .chartYAxis { mainChartYAxis }
        .chartXAxis(.hidden)
        .chartYScale(domain: minValue ... maxValue)
        .chartLegend(.hidden)
    }

    private var dummyBasalChart: some View {
        Chart {}
            .id("DummyBasalChart")
            .frame(height: UIScreen.main.bounds.height * 0.08)
            .frame(width: screenSize.width - 10)
            .chartYAxis(.hidden)
            .chartXAxis(.hidden)
            .chartYScale(domain: minValue ... maxValue)
            .chartLegend(.hidden)
    }

    private var mainChart: some View {
        VStack {
            Chart {
                drawStartRuleMark()
                drawEndRuleMark()
                drawCurrentTimeMarker()
                drawCarbs()
                drawFpus()
                drawBoluses()
                drawTempTargets()
                drawActiveOverrides()
                drawOverrideRunStored()
                drawForecasts()
                drawGlucose()
                drawManualGlucose()

                /// show glucose value when hovering over it
                if let selectedGlucose {
                    RuleMark(x: .value("Selection", selectedGlucose.date ?? now, unit: .minute))
                        .foregroundStyle(Color.tabBar)
                        .offset(yStart: 70)
                        .lineStyle(.init(lineWidth: 2, dash: [5]))
                        .annotation(position: .top) {
                            selectionPopover
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
            .frame(minHeight: UIScreen.main.bounds.height * 0.2)
            .frame(width: fullWidth(viewWidth: screenSize.width))
            .chartXScale(domain: startMarker ... endMarker)
            .chartXAxis { mainChartXAxis }
            .chartYAxis(.hidden)
            .backport.chartXSelection(value: $selection)
            .chartYScale(domain: minValue ... maxValue)
            .chartForegroundStyleScale([
                "zt": Color.zt,
                "uam": Color.uam,
                "cob": .orange,
                "iob": .blue
            ])
            .chartLegend(.hidden)
        }
    }

    @ViewBuilder var selectionPopover: some View {
        if let sgv = selectedGlucose?.glucose {
            let glucoseToShow = Decimal(sgv) * conversionFactor
            VStack {
                Text(selectedGlucose?.date?.formatted(.dateTime.hour().minute(.twoDigits)) ?? "")
                HStack {
                    Text(glucoseToShow.formatted(.number.precision(units == .mmolL ? .fractionLength(1) : .fractionLength(0))))
                        .fontWeight(.bold)
                        .foregroundStyle(
                            Decimal(sgv) < lowGlucose ? Color
                                .red : (Decimal(sgv) > highGlucose ? Color.orange : Color.primary)
                        )
                    Text(units.rawValue).foregroundColor(.secondary)
                }
            }
            .padding(6)
            .background {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.1))
                    .shadow(color: .blue, radius: 2)
            }
        }
    }

    private var basalChart: some View {
        VStack {
            Chart {
                drawStartRuleMark()
                drawEndRuleMark()
                drawCurrentTimeMarker()
                drawTempBasals()
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
            .frame(height: UIScreen.main.bounds.height * 0.08)
            .frame(width: fullWidth(viewWidth: screenSize.width))
            .chartXScale(domain: startMarker ... endMarker)
            .chartXAxis { basalChartXAxis }
            .chartYAxis(.hidden)
        }
    }

    var legendPanel: some View {
        HStack(spacing: 10) {
            Spacer()

            LegendItem(color: .loopGreen, label: "BG")
            LegendItem(color: .insulin, label: "IOB")
            LegendItem(color: .zt, label: "ZT")
            LegendItem(color: .loopYellow, label: "COB")
            LegendItem(color: .uam, label: "UAM")

            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
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
            let yPosition = units == .mgdL ? 60 : 3.33

            PointMark(
                x: .value("Time", carb.date ?? Date(), unit: .second),
                y: .value("Value", yPosition)
            )
            .symbolSize((Config.carbsSize + CGFloat(carbAmount) * Config.carbsScale) * 10)
            .foregroundStyle(Color.orange)
            .annotation(position: .bottom) {
                Text(carbsFormatter.string(from: carbAmount as NSNumber)!).font(.caption2)
                    .foregroundStyle(Color.orange)
            }
        }
    }

    private func drawFpus() -> some ChartContent {
        /// fpus
        ForEach(state.fpusFromPersistence, id: \.id) { fpu in
            let fpuAmount = fpu.carbs
            let size = (Config.fpuSize + CGFloat(fpuAmount) * Config.carbsScale) * 1.8
            let yPosition = units == .mgdL ? 60 : 3.33

            PointMark(
                x: .value("Time", fpu.date ?? Date(), unit: .second),
                y: .value("Value", yPosition)
            )
            .symbolSize(size)
            .foregroundStyle(Color.brown)
        }
    }

    private func drawGlucose() -> some ChartContent {
        /// glucose point mark
        /// filtering for high and low bounds in settings
        ForEach(state.glucoseFromPersistence) { item in
            if smooth {
                if item.glucose > Int(highGlucose) {
                    PointMark(
                        x: .value("Time", item.date ?? Date(), unit: .second),
                        y: .value("Value", Decimal(item.glucose) * conversionFactor)
                    ).foregroundStyle(Color.orange.gradient).symbolSize(25).interpolationMethod(.cardinal)
                } else if item.glucose < Int(lowGlucose) {
                    PointMark(
                        x: .value("Time", item.date ?? Date(), unit: .second),
                        y: .value("Value", Decimal(item.glucose) * conversionFactor)
                    ).foregroundStyle(Color.red.gradient).symbolSize(25).interpolationMethod(.cardinal)
                } else {
                    PointMark(
                        x: .value("Time", item.date ?? Date(), unit: .second),
                        y: .value("Value", Decimal(item.glucose) * conversionFactor)
                    ).foregroundStyle(Color.green.gradient).symbolSize(25).interpolationMethod(.cardinal)
                }
            } else {
                if item.glucose > Int(highGlucose) {
                    PointMark(
                        x: .value("Time", item.date ?? Date(), unit: .second),
                        y: .value("Value", Decimal(item.glucose) * conversionFactor)
                    ).foregroundStyle(Color.orange.gradient).symbolSize(25)
                } else if item.glucose < Int(lowGlucose) {
                    PointMark(
                        x: .value("Time", item.date ?? Date(), unit: .second),
                        y: .value("Value", Decimal(item.glucose) * conversionFactor)
                    ).foregroundStyle(Color.red.gradient).symbolSize(25)
                } else {
                    PointMark(
                        x: .value("Time", item.date ?? Date(), unit: .second),
                        y: .value("Value", Decimal(item.glucose) * conversionFactor)
                    ).foregroundStyle(Color.green.gradient).symbolSize(25)
                }
            }
        }
    }

    private func timeForIndex(_ index: Int32) -> Date {
        let currentTime = Date()
        let timeInterval = TimeInterval(index * 300)
        return currentTime.addingTimeInterval(timeInterval)
    }

    private func getForecasts(for determinationID: NSManagedObjectID, in context: NSManagedObjectContext) -> [Forecast] {
        do {
            guard let determination = try context.existingObject(with: determinationID) as? OrefDetermination,
                  let forecastSet = determination.forecasts,
                  let forecasts = Array(forecastSet) as? [Forecast]
            else {
                return []
            }
            return forecasts
        } catch {
            debugPrint(
                "Failed \(DebuggingIdentifiers.failed) to fetch OrefDetermination with ID \(determinationID): \(error.localizedDescription)"
            )
            return []
        }
    }

    private func getForecastValues(for forecastID: NSManagedObjectID, in context: NSManagedObjectContext) -> [ForecastValue] {
        do {
            guard let forecast = try context.existingObject(with: forecastID) as? Forecast,
                  let forecastValueSet = forecast.forecastValues,
                  let forecastValues = Array(forecastValueSet) as? [ForecastValue]
            else {
                return []
            }
            return forecastValues.sorted(by: { $0.index < $1.index })
        } catch {
            debugPrint(
                "Failed \(DebuggingIdentifiers.failed) to fetch Forecast with ID \(forecastID): \(error.localizedDescription)"
            )
            return []
        }
    }

    private func drawForecasts() -> some ChartContent {
        let preprocessedData = preprocessForecastData()

        return ForEach(preprocessedData, id: \.id) { tuple in
            let forecastValue = tuple.forecastValue
            let forecast = tuple.forecast

            LineMark(
                x: .value("Time", timeForIndex(forecastValue.index)),
                y: .value("Value", Int(forecastValue.value))
            )
            .foregroundStyle(by: .value("Predictions", forecast.type ?? ""))
        }
    }

    private func preprocessForecastData() -> [(id: UUID, forecast: Forecast, forecastValue: ForecastValue)] {
        state.determinationsFromPersistence
            .compactMap { determination -> NSManagedObjectID? in
                determination.objectID
            }
            .flatMap { determinationID -> [(id: UUID, forecast: Forecast, forecastValue: ForecastValue)] in
                let forecasts = getForecasts(for: determinationID, in: context)

                return forecasts.flatMap { forecast in
                    getForecastValues(for: forecast.objectID, in: context).map { forecastValue in
                        (id: UUID(), forecast: forecast, forecastValue: forecastValue)
                    }
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

    private func drawTempBasals() -> some ChartContent {
        ForEach(prepareTempBasals(), id: \.rate) { basal in
            RectangleMark(
                xStart: .value("start", basal.start),
                xEnd: .value("end", basal.end),
                yStart: .value("rate-start", 0),
                yEnd: .value("rate-end", basal.rate)
            ).foregroundStyle(Color.insulin.opacity(0.2))

            LineMark(x: .value("Start Date", basal.start), y: .value("Amount", basal.rate))
                .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.insulin)

            LineMark(x: .value("End Date", basal.end), y: .value("Amount", basal.rate))
                .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.insulin)
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
        endMarker = Date(timeIntervalSince1970: TimeInterval(NSDate().timeIntervalSince1970 + 10800))
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
        let glucoseMapped = state.glucoseFromPersistence.map(\.glucose)
        guard let minGlucose = glucoseMapped.min(), let maxGlucose = glucoseMapped.max() else {
            // default values
            minValue = 45 * conversionFactor - 20 * conversionFactor
            maxValue = 270 * conversionFactor + 50 * conversionFactor
            return
        }

        minValue = Decimal(minGlucose) * conversionFactor - 20 * conversionFactor
        maxValue = Decimal(maxGlucose) * conversionFactor + 50 * conversionFactor

        debug(.default, "min \(minValue)")
        debug(.default, "max \(maxValue)")
    }

    private func basalChartPlotStyle(_ plotContent: ChartPlotContent) -> some View {
        plotContent
            .rotationEffect(.degrees(180))
            .scaleEffect(x: -1, y: 1)
            .chartXAxis(.hidden)
    }

    private var mainChartXAxis: some AxisContent {
        AxisMarks(values: .stride(by: .hour, count: screenHours == 24 ? 4 : 2)) { _ in
            if displayXgridLines {
                AxisGridLine(stroke: .init(lineWidth: 0.5, dash: [2, 3]))
            } else {
                AxisGridLine(stroke: .init(lineWidth: 0, dash: [2, 3]))
            }
        }
    }

    private var basalChartXAxis: some AxisContent {
        AxisMarks(values: .stride(by: .hour, count: screenHours == 24 ? 4 : 2)) { _ in
            if displayXgridLines {
                AxisGridLine(stroke: .init(lineWidth: 0.5, dash: [2, 3]))
            } else {
                AxisGridLine(stroke: .init(lineWidth: 0, dash: [2, 3]))
            }
            AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .narrow)), anchor: .top)
                .font(.footnote)
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
                AxisValueLabel().font(.footnote)
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
