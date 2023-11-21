import Charts
import SwiftUI

struct MainChartView2: View {
    @Binding var tempBasals: [PumpHistoryEvent]
    @Binding var glucose: [BloodGlucose]
    @Binding var screenHours: Int16
    @Binding var highGlucose: Decimal
    @Binding var lowGlucose: Decimal
    @Binding var carbs: [CarbsEntry]
    @Binding var basalProfile: [BasalProfileEntry]

    var body: some View {
        VStack(alignment: .center, spacing: 8, content: {
            ZStack {
                GlucoseChart(glucose: $glucose, screenHours: $screenHours, highGlucose: $highGlucose, lowGlucose: $lowGlucose)
                VStack {
                    Spacer()
                        .frame(height: 280)
                    CarbsChart(carbs: $carbs, screenHours: $screenHours)
                }
            }
//            GlucoseChart(glucose: $glucose, screenHours: $screenHours, highGlucose: $highGlucose, lowGlucose: $lowGlucose)
//                .padding(.bottom, 20)
//            CarbsChart(carbs: $carbs, screenHours: $screenHours)
//                .padding(.bottom, 8)

            BasalChart(tempBasals: $tempBasals, screenHours: $screenHours)
                .padding(.bottom, 8)

//            ZStack {
//                BasalChart(tempBasals: $tempBasals, basalProfile: $basalProfile, screenHours: $screenHours)
//                BasalProfileChart(basalProfile: $basalProfile)
//            }
            Legend()
        })
    }
}

// MARK: GLUCOSE FOR CHART

struct GlucoseChart: View {
    @Binding var glucose: [BloodGlucose]
    @Binding var screenHours: Int16
    @Binding var highGlucose: Decimal
    @Binding var lowGlucose: Decimal

    var body: some View {
        VStack {
            let filteredGlucose: [BloodGlucose] = filterGlucoseData(for: screenHours)

            Chart(filteredGlucose) {
                RuleMark(y: .value("High", highGlucose))
                    .foregroundStyle(Color.loopYellow)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))

                RuleMark(y: .value("Low", lowGlucose))
                    .foregroundStyle(Color.loopRed)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))

//                MARK: TO DO -> at the moment this rule mark is not visible because the chart is not scrollable

                if let currentTime = getCurrentTime() {
                    RuleMark(x: .value("Current Time", currentTime))
                        .foregroundStyle(Color.gray)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                }

                PointMark(
                    x: .value("Time", $0.dateString),
                    y: .value("Value", $0.value)
                )
                .foregroundStyle(
                    $0.value > Double(highGlucose) ? Color.yellow.gradient :
                        $0.value < Double(lowGlucose) ? Color.red.gradient : Color.green.gradient
                )
                .symbolSize(12)
            }
            .frame(height: 250)
            .chartXAxis(.hidden)
        }
    }

    private func filterGlucoseData(for hours: Int16) -> [BloodGlucose] {
        guard hours > 0 else {
            return glucose
        }

        let currentDate = Date()
        let startDate = Calendar.current.date(byAdding: .hour, value: -Int(hours), to: currentDate) ?? currentDate

        return glucose.filter { $0.dateString >= startDate }
    }

    private func getCurrentTime() -> String? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm"
        return dateFormatter.string(from: Date())
    }
}

// MARK: BASAL FOR CHART

struct BasalChart: View {
    @Binding var tempBasals: [PumpHistoryEvent]
    @Binding var screenHours: Int16

    var body: some View {
        VStack {
            let filteredBasal: [PumpHistoryEvent] = filterBasalData(for: screenHours)

            Chart(filteredBasal) {
                BarMark(
                    x: .value("Time", $0.timestamp),
                    y: .value("Value", $0.rate ?? 0)
                )
                .foregroundStyle(Color.blue.gradient)
                .cornerRadius(0)
            }
            .frame(height: 80)
            //            .rotationEffect(.degrees(180))
            //            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartPlotStyle { plotArea in
                plotArea.background(.blue.gradient.opacity(0.1))
            }
        }
    }

    private func filterBasalData(for hours: Int16) -> [PumpHistoryEvent] {
        guard hours > 0 else {
            return tempBasals
        }

        let currentDate = Date()
        let startDate = Calendar.current.date(byAdding: .hour, value: -Int(hours), to: currentDate) ?? currentDate

        return tempBasals.filter { $0.timestamp >= startDate }
    }
}

struct BasalProfileChart: View {
    @Binding var basalProfile: [BasalProfileEntry]
    @Binding var screenHours: Int16

    var body: some View {
        let filteredBasalProfile: [BasalProfileEntry] = filterBasalProfileData(for: screenHours)

        VStack {
//            MARK: DOES NOT WORK

//            filtering function seems not to work...displays nothing

            Chart(filteredBasalProfile) {
                LineMark(
                    x: .value("start", $0.minutes),
                    y: .value("rate", $0.rate)
                ).foregroundStyle(Color.blue.gradient)
            }
        }
    }

    private func filterBasalProfileData(for hours: Int16) -> [BasalProfileEntry] {
        guard hours > 0 else {
            return basalProfile
        }

        let currentDate = Date()
        let startDate = Calendar.current.date(byAdding: .hour, value: -Int(hours), to: currentDate) ?? currentDate

        return basalProfile.filter { entry in
            if let entryDate = dateFormatter.date(from: entry.start) {
                return entryDate >= startDate
            } else {
                return false
            }
        }
    }

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

// MARK: COB

struct CarbsChart: View {
    @Binding var carbs: [CarbsEntry]
    @Binding var screenHours: Int16
    static var triangle: BasicChartSymbolShape { .triangle }

    var body: some View {
        VStack {
//            MARK: DOES NOT WORK PROPERLY
//            scaling is not correct because of swift charts automatic scaling...

            let filteredCarbs: [CarbsEntry] = filterCarbData(for: screenHours)
            Chart(filteredCarbs) {
                PointMark(
                    x: .value("Time", $0.createdAt),
                    y: .value("Value", 10)
                )
                .foregroundStyle(Color.loopYellow.gradient)
                .symbolSize(50)
                .symbol(CarbsChart.triangle)
            }
            .frame(height: 80)
            .chartYAxis(.hidden)
            .chartXAxis(.hidden)
        }
    }

    private func filterCarbData(for hours: Int16) -> [CarbsEntry] {
        guard hours > 0 else {
            return carbs
        }

        let currentDate = Date()
        let startDate = Calendar.current.date(byAdding: .hour, value: -Int(hours), to: currentDate) ?? currentDate

        return carbs.filter { $0.createdAt >= startDate }
    }
}

// MARK: LEGEND PANEL FOR CHART

struct Legend: View {
    var body: some View {
        HStack {
            Image(systemName: "line.diagonal")
                .rotationEffect(Angle(degrees: 45))
                .foregroundColor(.green)
            Text("BG")
                .foregroundColor(.secondary)
            Spacer()
            Image(systemName: "line.diagonal")
                .rotationEffect(Angle(degrees: 45))
                .foregroundColor(.insulin)
            Text("IOB")
                .foregroundColor(.secondary)
            Spacer()
            Image(systemName: "line.diagonal")
                .rotationEffect(Angle(degrees: 45))
                .foregroundColor(.purple)
            Text("ZT")
                .foregroundColor(.secondary)
            Spacer()
            Image(systemName: "line.diagonal")
                .frame(height: 10)
                .rotationEffect(Angle(degrees: 45))
                .foregroundColor(.loopYellow)
            Text("COB")
                .foregroundColor(.secondary)
            Spacer()
            Image(systemName: "line.diagonal")
                .rotationEffect(Angle(degrees: 45))
                .foregroundColor(.orange)
            Text("UAM")
                .foregroundColor(.secondary)
        }
        .font(.caption2)
        .padding(.horizontal, 40)
        .padding(.vertical, 1)
    }
}
