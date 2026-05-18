import CoreData
import SwiftUI

extension History.RootView {
    var mealsList: some View {
        List {
            HStack {
                Text("Type").foregroundStyle(.secondary)
                Spacer()
                filterFutureEntriesButton
            }
            if !carbEntryStored.isEmpty {
                ForEach(carbEntryStored.filter({ !showFutureEntries ? $0.date ?? Date() <= Date() : true })) { item in
                    mealView(item)
                }
            } else {
                ContentUnavailableView(
                    String(localized: "No data."),
                    systemImage: "fork.knife"
                )
            }
        }.listRowBackground(Color.chart)
    }

    @ViewBuilder func mealView(_ meal: CarbEntryStored) -> some View {
        VStack {
            HStack {
                if meal.isFPU {
                    Image(systemName: "circle.fill").foregroundColor(Color.orange.opacity(0.5))
                    Text("Fat / Protein")
                    Text(
                        (Formatter.decimalFormatterWithTwoFractionDigits.string(for: meal.carbs) ?? "0") +
                            String(localized: " g", comment: "gram of carbs")
                    )
                } else {
                    Image(systemName: "circle.fill").foregroundColor(Color.loopYellow)
                    Text("Carbs")
                    Text(
                        (Formatter.decimalFormatterWithTwoFractionDigits.string(for: meal.carbs) ?? "0") +
                            String(localized: " g", comment: "gram of carb equilvalents")
                    )
                }

                Spacer()

                Text(Formatter.dateFormatter.string(from: meal.date ?? Date()))
                    .moveDisabled(true)
            }
            if let note = meal.note, note != "" {
                HStack {
                    Image(systemName: "square.and.pencil")
                    Text(note)
                    Spacer()
                }.padding(.top, 5).foregroundColor(.secondary)
            }
        }
        .contextMenu {
            Button(
                "Delete",
                systemImage: "trash.fill",
                role: .destructive,
                action: { requestDelete(.carbs(meal)) }
            ).tint(.red)

            Button(
                "Edit",
                systemImage: "pencil",
                role: .none,
                action: {
                    state.carbEntryToEdit = meal
                    state.showCarbEntryEditor = true
                }
            )
            .tint(!state.settingsManager.settings.useFPUconversion && meal.isFPU ? Color(.systemGray4) : Color.blue)
            .disabled(!state.settingsManager.settings.useFPUconversion && meal.isFPU)
        }
        .swipeActions {
            Button(
                "Delete",
                systemImage: "trash.fill",
                role: .none,
                action: { requestDelete(.carbs(meal)) }
            ).tint(.red)

            Button(
                "Edit",
                systemImage: "pencil",
                role: .none,
                action: {
                    state.carbEntryToEdit = meal
                    state.showCarbEntryEditor = true
                }
            )
            .tint(!state.settingsManager.settings.useFPUconversion && meal.isFPU ? Color(.systemGray4) : Color.blue)
            .disabled(!state.settingsManager.settings.useFPUconversion && meal.isFPU)
        }
    }
}
