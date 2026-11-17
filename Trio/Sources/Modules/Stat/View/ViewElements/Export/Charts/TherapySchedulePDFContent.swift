import SwiftUI

/// PDF page for a therapy setting schedule: chart and table.
struct TherapySchedulePDFContent: View {
    let data: Stat.StateModel.TherapyScheduleExportData

    /// Longer tables are split into two columns.
    private static let rowsPerColumn = 16

    private let dayStart = Calendar.current.startOfDay(for: Date())

    var body: some View {
        if data.entries.isEmpty {
            Text("No schedule saved.")
                .foregroundStyle(Color.secondary)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                chart
                    .frame(height: 220)

                Divider()

                table

                if data.schedule == .basalRates {
                    totalRow
                }
            }
        }
    }

    // MARK: - Chart

    @ViewBuilder private var chart: some View {
        switch data.schedule {
        case .basalRates:
            TherapyProfileChart(
                entries: data.entries,
                color: .purple,
                usesGradientFill: false,
                accessibilityLabel: Text("Basal rate profile chart, 24 hours")
            )
        case .carbRatios:
            TherapyProfileChart(
                entries: data.entries,
                color: .orange,
                usesGradientFill: false,
                accessibilityLabel: Text("Carb ratio profile chart, 24 hours")
            )
        case .insulinSensitivities:
            TherapyProfileChart(
                entries: data.entries,
                color: .cyan,
                usesGradientFill: false,
                accessibilityLabel: Text("Insulin sensitivity profile chart, 24 hours")
            )
        case .glucoseTargets:
            TherapyProfileChart(
                entries: data.entries,
                color: .green,
                fillsArea: false,
                lineWidth: 2.5,
                yDomain: targetsYDomain,
                accessibilityLabel: Text("Glucose target profile chart, 24 hours")
            )
        }
    }

    /// The settings screen's fixed 72–180 mg/dL axis, widened if a target falls outside it.
    private var targetsYDomain: ClosedRange<Decimal> {
        let lower = data.units == .mgdL ? Decimal(72) : Decimal(72).asMmolL
        let upper = data.units == .mgdL ? Decimal(180) : Decimal(180).asMmolL
        let values = data.entries.map(\.value)
        return min(lower, values.min() ?? lower) ... max(upper, values.max() ?? upper)
    }

    // MARK: - Table

    private var table: some View {
        let columns = data.entries.count > Self.rowsPerColumn
            ? [
                Array(data.entries.prefix((data.entries.count + 1) / 2)),
                Array(data.entries.dropFirst((data.entries.count + 1) / 2))
            ]
            : [data.entries]

        return HStack(alignment: .top, spacing: 32) {
            ForEach(columns.indices, id: \.self) { index in
                tableColumn(columns[index])
            }
        }
        .font(.caption)
    }

    private func tableColumn(_ entries: [TherapyProfileChart.Entry]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 4) {
            GridRow {
                Text("Start").fontWeight(.semibold)
                Text(data.unit.displayName).fontWeight(.semibold)
                    .gridColumnAlignment(.trailing)
            }
            Divider()
            ForEach(entries.indices, id: \.self) { index in
                GridRow {
                    Text(dayStart.addingTimeInterval(entries[index].start), format: .dateTime.hour().minute())
                    Text(format(entries[index].value))
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: - Basal total

    private var totalRow: some View {
        HStack {
            Text("Total").fontWeight(.semibold)
            Spacer()
            Text(format(basalTotal))
                .monospacedDigit()
            Text("U/day")
        }
        .font(.caption)
        .frame(maxWidth: 240)
    }

    /// Calculated like the basal editor's total.
    private var basalTotal: Decimal {
        let dayEnd: TimeInterval = 24 * 60 * 60
        let ends: [TimeInterval] = data.entries.dropFirst().map(\.start) + [dayEnd]
        var total: Decimal = 0
        for (entry, end) in zip(data.entries, ends) {
            let hours = Decimal((end - entry.start) / 3600)
            total += entry.value * hours
        }
        return total
    }

    private func format(_ value: Decimal) -> String {
        let maxFractionDigits: Int
        switch data.unit {
        case .unitPerHour: maxFractionDigits = 3
        case .mgdL,
             .mgdLPerUnit: maxFractionDigits = 0
        case .gramPerUnit,
             .mmolL,
             .mmolLPerUnit: maxFractionDigits = 1
        }
        return value.formatted(.number.precision(.fractionLength(0 ... maxFractionDigits)))
    }
}
