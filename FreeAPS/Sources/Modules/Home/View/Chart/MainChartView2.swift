import Charts
import SwiftUI

struct MainChartView2: View {
    @Binding var tempBasals: [PumpHistoryEvent]
    @Binding var glucose: [BloodGlucose]
    @Binding var screenHours: Int16
    @Binding var highGlucose: Decimal
    @Binding var lowGlucose: Decimal
    @Binding var carbs: [CarbsEntry]

    var body: some View {
        VStack(alignment: .center, spacing: 8, content: {
            GlucoseChart(glucose: $glucose, screenHours: $screenHours, highGlucose: $highGlucose, lowGlucose: $lowGlucose)
                .padding(.bottom, 20)
            CarbsChart(carbs: $carbs, screenHours: $screenHours)
                .padding(.bottom, 8)
            BasalChart(tempBasals: $tempBasals, screenHours: $screenHours)
                .padding(.bottom, 8)
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

// MARK: COB

struct CarbsChart: View {
    @Binding var carbs: [CarbsEntry]
    @Binding var screenHours: Int16

    var body: some View {
        let currentDate = Date()
        let startDate = Calendar.current.date(byAdding: .hour, value: -Int(screenHours), to: currentDate) ?? currentDate

        VStack {
            let filteredCarbs: [CarbsEntry] = filterCarbData(for: screenHours)
            Chart(filteredCarbs) {
                BarMark(
                    x: .value("Time", $0.createdAt),
                    y: .value("Value", $0.carbs)
                )
                .foregroundStyle(Color.loopYellow.gradient)
                .cornerRadius(0)
            }
            .frame(height: 80)
            .chartYAxis(.hidden)
//            .chartXScale(domain: Int(startDate.timeIntervalSince1970) ... Int(currentDate.timeIntervalSince1970))
//            .chartXScale(domain: 0 ... 5)
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
