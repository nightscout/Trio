import CoreData
import SwiftUI

extension History.RootView {
    var treatmentsList: some View {
        List {
            HStack {
                filterTreatmentsButton
                Spacer()
                Text("Time").foregroundStyle(.secondary)
            }
            if !filteredPumpEvents.isEmpty {
                ForEach(filteredPumpEvents) { item in
                    treatmentView(item)
                }
            } else {
                ContentUnavailableView(
                    String(localized: "No data."),
                    systemImage: "syringe"
                )
            }
        }.listRowBackground(Color.chart)
    }

    var filteredPumpEvents: [PumpEventStored] {
        pumpEventStored.filter { item in
            // First filter by date
            let passesDateFilter = !showFutureEntries ? item.timestamp ?? Date() <= Date() : true

            guard passesDateFilter else { return false }

            // Then filter by treatment type
            if let bolus = item.bolus {
                if bolus.isSMB {
                    return selectedTreatmentTypes.contains(.smb)
                } else if bolus.isExternal {
                    return selectedTreatmentTypes.contains(.externalBolus)
                } else {
                    return selectedTreatmentTypes.contains(.bolus)
                }
            } else if item.tempBasal != nil {
                return selectedTreatmentTypes.contains(.tempBasal)
            } else if item.type == "PumpSuspend" {
                return selectedTreatmentTypes.contains(.suspend)
            } else {
                return selectedTreatmentTypes.contains(.other)
            }
        }
    }

    @ViewBuilder func treatmentView(_ item: PumpEventStored) -> some View {
        HStack {
            if let bolus = item.bolus, let amount = bolus.amount {
                Image(systemName: "circle.fill").foregroundColor(Color.insulin)
                Text(bolus.isSMB ? "SMB" : item.type ?? "Bolus")
                Text(
                    (Formatter.decimalFormatterWithThreeFractionDigits.string(from: amount) ?? "0") +
                        String(localized: " U", comment: "Insulin unit")
                )
                .foregroundColor(.secondary)
                if bolus.isExternal {
                    Text(String(localized: "External", comment: "External Insulin")).foregroundColor(.secondary)
                }
            } else if let tempBasal = item.tempBasal, let rate = tempBasal.rate {
                Image(systemName: "circle.fill").foregroundColor(Color.insulin.opacity(0.4))
                Text("Temp Basal")
                Text(
                    (Formatter.decimalFormatterWithThreeFractionDigits.string(from: rate) ?? "0") +
                        String(localized: " U/hr", comment: "Unit insulin per hour")
                )
                .foregroundColor(.secondary)
                if tempBasal.duration > 0 {
                    Text("\(tempBasal.duration.string) min").foregroundColor(.secondary)
                }
            } else {
                Image(systemName: "circle.fill").foregroundColor(Color.loopGray)
                Text(item.type ?? "Pump Event")
            }
            Spacer()
            Text(Formatter.dateFormatter.string(from: item.timestamp ?? Date())).moveDisabled(true)
        }
        .contextMenu {
            if item.bolus != nil {
                Button(
                    "Delete",
                    systemImage: "trash.fill",
                    role: .destructive,
                    action: { requestDelete(.insulin(item)) }
                ).tint(.red)
            }
        }
        .swipeActions {
            if item.bolus != nil {
                Button(
                    "Delete",
                    systemImage: "trash.fill",
                    role: .none,
                    action: { requestDelete(.insulin(item)) }
                ).tint(.red)
            }
        }
    }
}
