import CoreData
import SwiftUI

extension History.RootView {
    var glucoseList: some View {
        List {
            HStack {
                Text("Values")
                Spacer()
                Text("Time")
            }.foregroundStyle(.secondary)

            if !glucoseStored.isEmpty {
                ForEach(glucoseStored) { glucose in
                    HStack {
                        Text(formatGlucose(Decimal(glucose.glucose), isManual: glucose.isManual))

                        /// check for manual glucose
                        if glucose.isManual {
                            Image(systemName: "drop.fill").symbolRenderingMode(.monochrome).foregroundStyle(.red)
                        } else {
                            Text("\(glucose.directionEnum?.symbol ?? "--")")
                        }

                        if state.settingsManager.settings.smoothGlucose, !glucose.isManual,
                           let smoothedGlucose = glucose.smoothedGlucose, smoothedGlucose != 0
                        {
                            let smoothedGlucoseForDisplay = state.units == .mgdL ? smoothedGlucose
                                .description : smoothedGlucose.decimalValue
                                .formattedAsMmolL

                            (
                                Text("(") +
                                    Text(Image(systemName: "sparkles")) +
                                    Text(" ") +
                                    Text("\(smoothedGlucoseForDisplay)") +
                                    Text(")")
                            ).foregroundStyle(.secondary)
                                .padding(.leading, 10)
                        }

                        Spacer()

                        Text(Formatter.dateFormatter.string(from: glucose.date ?? Date()))
                    }
                    .contextMenu {
                        Button(
                            "Delete",
                            systemImage: "trash.fill",
                            role: .destructive,
                            action: { requestDelete(.glucose(glucose)) }
                        ).tint(.red)
                    }
                    .swipeActions {
                        Button(
                            "Delete",
                            systemImage: "trash.fill",
                            role: .none,
                            action: { requestDelete(.glucose(glucose)) }
                        ).tint(.red)
                    }
                }
            } else {
                ContentUnavailableView(
                    String(localized: "No data."),
                    systemImage: "drop.fill"
                )
            }
        }.listRowBackground(Color.chart)
    }

    func formatGlucose(_ value: Decimal, isManual: Bool) -> String {
        let formatter = isManual ? manualGlucoseFormatter : Formatter.glucoseFormatter(for: state.units)
        let glucoseValue = state.units == .mmolL ? value.asMmolL : value
        let formattedValue = formatter.string(from: glucoseValue as NSNumber) ?? "--"

        return formattedValue
    }
}
