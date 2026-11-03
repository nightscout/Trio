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
                    let manualOrTrend = glucose.isManual
                        ? String(localized: "manual entry", comment: "Accessibility: manually entered glucose")
                        : (glucose.directionEnum?.symbol ?? "--")
                    HStack {
                        Text(Decimal(glucose.glucose).formatted(for: state.units))

                        /// check for manual glucose
                        if glucose.isManual {
                            Image(systemName: "drop.fill").symbolRenderingMode(.monochrome).foregroundStyle(.red)
                        } else {
                            Text("\(glucose.directionEnum?.symbol ?? "--")")
                        }

                        if state.settingsManager.settings.smoothGlucose, !glucose.isManual,
                           let smoothedGlucose = glucose.smoothedGlucose, smoothedGlucose != 0
                        {
                            let smoothedGlucoseForDisplay = smoothedGlucose.decimalValue.formatted(for: state.units)

                            (
                                Text("(") +
                                    Text(Image(systemName: "sparkles")) +
                                    Text(" ") +
                                    Text(smoothedGlucoseForDisplay) +
                                    Text(")")
                            ).foregroundStyle(.secondary)
                                .padding(.leading, 10)
                        }

                        Spacer()

                        Text(Formatter.dateFormatter.string(from: glucose.date ?? Date()))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(
                        Decimal(glucose.glucose).formatted(for: state.units)
                            + ", " + manualOrTrend
                            + ", " + Formatter.dateFormatter.string(from: glucose.date ?? Date())
                    ))
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
}
