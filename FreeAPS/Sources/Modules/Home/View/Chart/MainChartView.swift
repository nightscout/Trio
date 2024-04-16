import Charts
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

private struct Prediction: Hashable {
    let amount: Int
    let timestamp: Date
    let type: PredictionType
}

private struct ChartTempTarget: Hashable {
    let amount: Decimal
    let start: Date
    let end: Date
}

private enum PredictionType: Hashable {
    case iob
    case cob
    case zt
    case uam
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

    @Binding var glucose: [BloodGlucose]
    @Binding var manualGlucose: [BloodGlucose]
    @Binding var fpusForChart: [CarbsEntry]
    @Binding var units: GlucoseUnits
    @Binding var eventualBG: Int?
    @Binding var suggestion: Suggestion?
    @Binding var tempBasals: [PumpHistoryEvent]
    @Binding var boluses: [PumpHistoryEvent]
    @Binding var suspensions: [PumpHistoryEvent]
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

    @StateObject var state = Home.StateModel()

    @State var didAppearTrigger = false
    @State private var BasalProfiles: [BasalProfile] = []
    @State private var TempBasals: [PumpHistoryEvent] = []
    @State private var ChartTempTargets: [ChartTempTarget] = []
    @State private var Predictions: [Prediction] = []
    @State private var count: Decimal = 1
    @State private var startMarker = Date(timeIntervalSince1970: TimeInterval(NSDate().timeIntervalSince1970 - 86400))
    @State private var endMarker = Date(timeIntervalSince1970: TimeInterval(NSDate().timeIntervalSince1970 + 10800))
    @State private var minValue: Decimal = 45
    @State private var maxValue: Decimal = 270
    @State private var selection: Date? = nil

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.calendar) var calendar

    // MARK: - Core Data Fetch Requests

    @FetchRequest(
        entity: MealsStored.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \MealsStored.date, ascending: true)]
    ) var carbsFromPersistence: FetchedResults<MealsStored>

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

    private var selectedGlucose: BloodGlucose? {
        if let selection = selection {
            let lowerBound = selection.addingTimeInterval(-120)
            let upperBound = selection.addingTimeInterval(120)
            return glucose.first { $0.dateString >= lowerBound && $0.dateString <= upperBound }
        } else {
            return nil
        }
    }

    var body: some View {
        VStack {
            ScrollViewReader { scroller in
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 0) {
                        mainChart
                        basalChart

                    }.onChange(of: screenHours) { _ in
                        updateStartEndMarkers()
                        yAxisChartData()
                        scroller.scrollTo("MainChart", anchor: .trailing)
                    }.onChange(of: glucose) { _ in
                        updateStartEndMarkers()
                        yAxisChartData()
                        scroller.scrollTo("MainChart", anchor: .trailing)
                    }
                    .onChange(of: suggestion) { _ in
                        updateStartEndMarkers()
                        scroller.scrollTo("MainChart", anchor: .trailing)
                    }
                    .onChange(of: tempBasals) { _ in
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
                drawPredictions()
                drawGlucose()
                drawManualGlucose()

                /// high and low treshold lines
                if thresholdLines {
                    RuleMark(y: .value("High", highGlucose * conversionFactor)).foregroundStyle(Color.loopYellow)
                        .lineStyle(.init(lineWidth: 1, dash: [5]))
                    RuleMark(y: .value("Low", lowGlucose * conversionFactor)).foregroundStyle(Color.loopRed)
                        .lineStyle(.init(lineWidth: 1, dash: [5]))
                }

                /// show glucose value when hovering over it
                if let selectedGlucose {
                    RuleMark(x: .value("Selection", selectedGlucose.dateString, unit: .minute))
                        .foregroundStyle(Color.tabBar)
                        .offset(yStart: 70)
                        .lineStyle(.init(lineWidth: 2, dash: [5]))
                        .annotation(position: .top) {
                            selectionPopover
                        }
                }
            }
            .id("MainChart")
            .onChange(of: glucose) { _ in
                calculatePredictions()
            }
            .onChange(of: boluses) { _ in
                state.roundedTotalBolus = state.calculateTINS()
            }
            .onChange(of: tempTargets) { _ in
                calculateTTs()
            }
            .onChange(of: didAppearTrigger) { _ in
                calculatePredictions()
                calculateTTs()
            }.onChange(of: suggestion) { _ in
                calculatePredictions()
            }
            .onReceive(
                Foundation.NotificationCenter.default
                    .publisher(for: UIApplication.willEnterForegroundNotification)
            ) { _ in
                calculatePredictions()
            }
            .frame(minHeight: UIScreen.main.bounds.height * 0.2)
            .frame(width: fullWidth(viewWidth: screenSize.width))
            .chartXScale(domain: startMarker ... endMarker)
            .chartXAxis { mainChartXAxis }
            // .chartXAxis(.hidden)
            .chartYAxis { mainChartYAxis }
            .chartYScale(domain: minValue ... maxValue)
            .backport.chartXSelection(value: $selection)
        }
    }

    @ViewBuilder var selectionPopover: some View {
        if let sgv = selectedGlucose?.sgv {
            let glucoseToShow = Decimal(sgv) * conversionFactor
            VStack {
                Text(selectedGlucose?.dateString.formatted(.dateTime.hour().minute(.twoDigits)) ?? "")
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
            }.onChange(of: tempBasals) { _ in
                calculateBasals()
                calculateTempBasals()
            }
            .onChange(of: maxBasal) { _ in
                calculateBasals()
                calculateTempBasals()
            }
            .onChange(of: autotunedBasalProfile) { _ in
                calculateBasals()
                calculateTempBasals()
            }
            .onChange(of: didAppearTrigger) { _ in
                calculateBasals()
                calculateTempBasals()
            }.onChange(of: basalProfile) { _ in
                calculateTempBasals()
            }
            .frame(height: UIScreen.main.bounds.height * 0.08)
            .frame(width: fullWidth(viewWidth: screenSize.width))
            .chartXScale(domain: startMarker ... endMarker)
            .chartXAxis { basalChartXAxis }
            .chartYAxis { basalChartYAxis }
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
        /// smbs in triangle form
        ForEach(boluses) { bolus in
            let bolusAmount = bolus.amount ?? 0
            let glucose = timeToNearestGlucose(time: bolus.timestamp.timeIntervalSince1970)
            let yPosition = (Decimal(glucose.sgv ?? defaultBolusPosition) * conversionFactor) + bolusOffset
            let size = (Config.bolusSize + CGFloat(bolusAmount) * Config.bolusScale) * 1.8

            return PointMark(
                x: .value("Time", bolus.timestamp, unit: .second),
                y: .value("Value", yPosition)
            )
            .symbol {
                Image(systemName: "arrowtriangle.down.fill").font(.system(size: size)).foregroundStyle(Color.insulin)
            }
            .annotation(position: .top) {
                Text(bolusFormatter.string(from: bolusAmount as NSNumber)!).font(.caption2)
                    .foregroundStyle(Color.insulin)
            }
        }
    }

    private func drawCarbs() -> some ChartContent {
        /// carbs
        ForEach(carbsFromPersistence) { carb in
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
        ForEach(fpusForChart) { fpu in
            let fpuAmount = fpu.carbs
            let size = (Config.fpuSize + CGFloat(fpuAmount) * Config.carbsScale) * 1.8
            let yPosition = units == .mgdL ? 60 : 3.33

            PointMark(
                x: .value("Time", fpu.actualDate ?? Date(), unit: .second),
                y: .value("Value", yPosition)
            )
            .symbolSize(size)
            .foregroundStyle(Color.brown)
        }
    }

    private func drawGlucose() -> some ChartContent {
        /// glucose point mark
        /// filtering for high and low bounds in settings
        ForEach(glucose) { item in
            if let sgv = item.sgv {
                let sgvLimited = max(sgv, 0)

                if smooth {
                    if sgvLimited > Int(highGlucose) {
                        PointMark(
                            x: .value("Time", item.dateString, unit: .second),
                            y: .value("Value", Decimal(sgvLimited) * conversionFactor)
                        ).foregroundStyle(Color.orange.gradient).symbolSize(25).interpolationMethod(.cardinal)
                    } else if sgvLimited < Int(lowGlucose) {
                        PointMark(
                            x: .value("Time", item.dateString, unit: .second),
                            y: .value("Value", Decimal(sgvLimited) * conversionFactor)
                        ).foregroundStyle(Color.red.gradient).symbolSize(25).interpolationMethod(.cardinal)
                    } else {
                        PointMark(
                            x: .value("Time", item.dateString, unit: .second),
                            y: .value("Value", Decimal(sgvLimited) * conversionFactor)
                        ).foregroundStyle(Color.green.gradient).symbolSize(25).interpolationMethod(.cardinal)
                    }
                } else {
                    if sgvLimited > Int(highGlucose) {
                        PointMark(
                            x: .value("Time", item.dateString, unit: .second),
                            y: .value("Value", Decimal(sgvLimited) * conversionFactor)
                        ).foregroundStyle(Color.orange.gradient).symbolSize(25)
                    } else if sgvLimited < Int(lowGlucose) {
                        PointMark(
                            x: .value("Time", item.dateString, unit: .second),
                            y: .value("Value", Decimal(sgvLimited) * conversionFactor)
                        ).foregroundStyle(Color.red.gradient).symbolSize(25)
                    } else {
                        PointMark(
                            x: .value("Time", item.dateString, unit: .second),
                            y: .value("Value", Decimal(sgvLimited) * conversionFactor)
                        ).foregroundStyle(Color.green.gradient).symbolSize(25)
                    }
                }
            }
        }
    }

    private func drawPredictions() -> some ChartContent {
        /// predictions
        ForEach(Predictions, id: \.self) { info in
            let y = max(info.amount, 0)

            if info.type == .uam {
                LineMark(
                    x: .value("Time", info.timestamp, unit: .second),
                    y: .value("Value", Decimal(y) * conversionFactor),
                    series: .value("uam", "uam")
                ).foregroundStyle(Color.uam).symbolSize(16)
            }
            if info.type == .cob {
                LineMark(
                    x: .value("Time", info.timestamp, unit: .second),
                    y: .value("Value", Decimal(y) * conversionFactor),
                    series: .value("cob", "cob")
                ).foregroundStyle(Color.orange).symbolSize(16)
            }
            if info.type == .iob {
                LineMark(
                    x: .value("Time", info.timestamp, unit: .second),
                    y: .value("Value", Decimal(y) * conversionFactor),
                    series: .value("iob", "iob")
                ).foregroundStyle(Color.insulin).symbolSize(16)
            }
            if info.type == .zt {
                LineMark(
                    x: .value("Time", info.timestamp, unit: .second),
                    y: .value("Value", Decimal(y) * conversionFactor),
                    series: .value("zt", "zt")
                ).foregroundStyle(Color.zt).symbolSize(16)
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
        ForEach(ChartTempTargets, id: \.self) { target in
            let targetLimited = min(max(target.amount, 0), upperLimit)

            RuleMark(
                xStart: .value("Start", target.start),
                xEnd: .value("End", target.end),
                y: .value("Value", targetLimited)
            )
            .foregroundStyle(Color.purple.opacity(0.5)).lineStyle(.init(lineWidth: 8))
        }
    }

    private func drawManualGlucose() -> some ChartContent {
        /// manual glucose mark
        ForEach(manualGlucose) { item in
            if let manualGlucose = item.glucose {
                PointMark(
                    x: .value("Time", item.dateString, unit: .second),
                    y: .value("Value", Decimal(manualGlucose) * conversionFactor)
                )
                .symbol {
                    Image(systemName: "drop.fill").font(.system(size: 10)).symbolRenderingMode(.monochrome)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func drawSuspensions() -> some ChartContent {
        /// pump suspensions
        ForEach(suspensions) { suspension in
            let now = Date()

            if suspension.type == EventType.pumpSuspend {
                let suspensionStart = suspension.timestamp
                let suspensionEnd = min(
                    suspensions
                        .first(where: { $0.timestamp > suspension.timestamp && $0.type == EventType.pumpResume })?
                        .timestamp ?? now,
                    now
                )
                let basalProfileDuringSuspension = BasalProfiles.first(where: { $0.startDate <= suspensionStart })
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

    private func drawTempBasals() -> some ChartContent {
        /// temp basal rects
        ForEach(TempBasals) { temp in
            /// calculate end time of temp basal adding duration to start time
            let end = temp.timestamp + (temp.durationMin ?? 0).minutes.timeInterval
            let now = Date()

            /// ensure that temp basals that are set cannot exceed current date -> i.e. scheduled temp basals are not shown
            /// we could display scheduled temp basals with opacity etc... in the future
            let maxEndTime = min(end, now)

            /// set mark height to 0 when insulin delivery is suspended
            let isInsulinSuspended = suspensions
                .first(where: { $0.timestamp >= temp.timestamp && $0.timestamp <= maxEndTime }) != nil
            let rate = (temp.rate ?? 0) * (isInsulinSuspended ? 0 : 1)

            /// find next basal entry and if available set end of current entry to start of next entry
            if let nextTemp = TempBasals.first(where: { $0.timestamp > temp.timestamp }) {
                let nextTempStart = nextTemp.timestamp

                RectangleMark(
                    xStart: .value("start", temp.timestamp),
                    xEnd: .value("end", nextTempStart),
                    yStart: .value("rate-start", 0),
                    yEnd: .value("rate-end", rate)
                ).foregroundStyle(Color.insulin.opacity(0.2))

                LineMark(x: .value("Start Date", temp.timestamp), y: .value("Amount", rate))
                    .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.insulin)

                LineMark(x: .value("End Date", nextTempStart), y: .value("Amount", rate))
                    .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.insulin)
            } else {
                RectangleMark(
                    xStart: .value("start", temp.timestamp),
                    xEnd: .value("end", maxEndTime),
                    yStart: .value("rate-start", 0),
                    yEnd: .value("rate-end", rate)
                ).foregroundStyle(Color.insulin.opacity(0.2))

                LineMark(x: .value("Start Date", temp.timestamp), y: .value("Amount", rate))
                    .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.insulin)

                LineMark(x: .value("End Date", maxEndTime), y: .value("Amount", rate))
                    .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.insulin)
            }
        }
    }

    private func drawBasalProfile() -> some ChartContent {
        /// dashed profile line
        ForEach(BasalProfiles, id: \.self) { profile in
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
    /// if time is later than all the arrays values return the last element of BloodGlucose
    private func timeToNearestGlucose(time: TimeInterval) -> BloodGlucose {
        /// If the glucose array is empty, return a default BloodGlucose object or handle it accordingly
        guard let lastGlucose = glucose.last else {
            return BloodGlucose(
                date: 0,
                dateString: Date(),
                unfiltered: nil,
                filtered: nil,
                noise: nil,
                type: nil
            )
        }

        /// If the last glucose entry is before the specified time, return the last entry
        if lastGlucose.dateString.timeIntervalSince1970 < time {
            return lastGlucose
        }

        /// Find the index of the first element in the array whose date is greater than the specified time
        if let nextIndex = glucose.firstIndex(where: { $0.dateString.timeIntervalSince1970 > time }) {
            return glucose[nextIndex]
        } else {
            /// If no such element is found, return the last element in the array
            return lastGlucose
        }
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

        ChartTempTargets = calculatedTTs
    }

    private func addPredictions(_ predictions: [Int], type: PredictionType, deliveredAt: Date, endMarker: Date) -> [Prediction] {
        var calculatedPredictions: [Prediction] = []
        predictions.indices.forEach { index in
            let predTime = Date(
                timeIntervalSince1970: deliveredAt.timeIntervalSince1970 + TimeInterval(index) * 5.minutes.timeInterval
            )
            if predTime.timeIntervalSince1970 < endMarker.timeIntervalSince1970 {
                calculatedPredictions.append(
                    Prediction(amount: predictions[index], timestamp: predTime, type: type)
                )
            }
        }
        return calculatedPredictions
    }

    private func calculatePredictions() {
        guard let suggestion = suggestion, let deliveredAt = suggestion.deliverAt else { return }
        let uamPredictions = suggestion.predictions?.uam ?? []
        let iobPredictions = suggestion.predictions?.iob ?? []
        let cobPredictions = suggestion.predictions?.cob ?? []
        let ztPredictions = suggestion.predictions?.zt ?? []

        let uam = addPredictions(uamPredictions, type: .uam, deliveredAt: deliveredAt, endMarker: endMarker)
        let iob = addPredictions(iobPredictions, type: .iob, deliveredAt: deliveredAt, endMarker: endMarker)
        let cob = addPredictions(cobPredictions, type: .cob, deliveredAt: deliveredAt, endMarker: endMarker)
        let zt = addPredictions(ztPredictions, type: .zt, deliveredAt: deliveredAt, endMarker: endMarker)

        Predictions = uam + iob + cob + zt
    }

    private func calculateTempBasals() {
        let basals = tempBasals
        var returnTempBasalRates: [PumpHistoryEvent] = []
        var finished: [Int: Bool] = [:]
        basals.indices.forEach { i in
            basals.indices.forEach { j in
                if basals[i].timestamp == basals[j].timestamp, i != j, !(finished[i] ?? false), !(finished[j] ?? false) {
                    let rate = basals[i].rate ?? basals[j].rate
                    let durationMin = basals[i].durationMin ?? basals[j].durationMin
                    finished[i] = true
                    if rate != 0 || durationMin != 0 {
                        returnTempBasalRates.append(
                            PumpHistoryEvent(
                                id: basals[i].id, type: FreeAPS.EventType.tempBasal,
                                timestamp: basals[i].timestamp,
                                durationMin: durationMin,
                                rate: rate
                            )
                        )
                    }
                }
            }
        }
        TempBasals = returnTempBasalRates
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
            print(
                "Basal",
                totalBasal[index].startDate,
                totalBasal.count > index + 1 ? totalBasal[index + 1].startDate : endMarker,
                totalBasal[index].amount,
                totalBasal[index].isOverwritten
            )
        }
        BasalProfiles = basals
    }

    // MARK: - Chart formatting

    private func yAxisChartData() {
        let glucoseMapped = glucose.compactMap(\.glucose)
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

    private var basalChartYAxis: some AxisContent {
        AxisMarks(position: .trailing) { _ in
            AxisTick(length: units == .mmolL ? 25 : 27, stroke: .init(lineWidth: 4))
                .foregroundStyle(Color.clear).font(.footnote)
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
