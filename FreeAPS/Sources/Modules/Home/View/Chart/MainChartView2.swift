import Charts
import SwiftUI

struct MainChartView2: View {
    // MARK: BINDINGS

    @Binding var glucose: [BloodGlucose]
    @Binding var screenHours: Int16

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack {
                    let filteredGlucose: [BloodGlucose] = filterGlucoseData(for: screenHours)

                    Chart(filteredGlucose) {
                        PointMark(
                            x: .value("Time", $0.dateString),
                            y: .value("Value", $0.value)
                        )
                        .foregroundStyle(Color.green.gradient)
                        .cornerRadius(0)
                    }

                    .frame(height: 350)
                    .chartXAxis {
//                        MARK: THIS PIECE OF CODE BELONGS TO THE UNIQUEHOURLABELS FUNC....BUT DOES NOT WORK

//                        let uniqueHourLabels = self.uniqueHourLabels(for: filteredGlucose)
//                        AxisMarks(values: uniqueHourLabels) { _ in
//                            AxisValueLabel(format: .dateTime.hour())
//                        }

                        AxisMarks(values: filteredGlucose.map(\.dateString)) { _ in
                            AxisValueLabel(format: .dateTime.hour())
                        }
                    }
                    Legend()
                }
                .padding()
            }
        }
    }

//    // MARK: THIS FUNCTION DOES NOT WORK BUT COULD MAYBE IMPROVED?
//
//    private func uniqueHourLabels(for glucoseData: [BloodGlucose]) -> [String] {
//        var uniqueLabels: Set<String> = Set()
//        var result: [String] = []
//
//        let dateFormatter = DateFormatter()
//        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
//        dateFormatter.setLocalizedDateFormatFromTemplate("HH")
//
//        let currentHour = Calendar.current.component(.hour, from: Date())
//
//        for entry in glucoseData {
//            let hourLabel = dateFormatter.string(from: entry.dateString)
//            if !uniqueLabels.contains(hourLabel), currentHour == Calendar.current.component(.hour, from: entry.dateString) {
//                uniqueLabels.insert(hourLabel)
//                result.append(hourLabel)
//            }
//        }
//
//        return result
//    }

    // MARK: WORKS NOW...

    private func filterGlucoseData(for hours: Int16) -> [BloodGlucose] {
        guard hours > 0 else {
            return glucose
        }

        let currentDate = Date()
        let startDate = Calendar.current.date(byAdding: .hour, value: -Int(hours), to: currentDate) ?? currentDate

//        print("die hours sind ++++++++++++++++++++")
//        print(hours)

        return glucose.filter { $0.dateString >= startDate }
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
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
    }
}
