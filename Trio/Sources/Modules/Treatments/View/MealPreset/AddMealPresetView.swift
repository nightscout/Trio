import CoreData
import Foundation
import Observation
import SwiftUI

struct AddMealPresetView: View {
    @Binding var dish: String
    @Binding var presetCarbs: Decimal
    @Binding var presetFat: Decimal
    @Binding var presetProtein: Decimal
    @Binding var displayFatAndProtein: Bool
    var onSave: () -> Void
    var onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) var appState

    private var mealFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumIntegerDigits = 3
        formatter.maximumFractionDigits = 0
        return formatter
    }

    private var isFormValid: Bool {
        !dish.isEmpty && (presetCarbs > 0 || presetProtein > 0 || presetFat > 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextFieldWithToolBarString(
                        text: $dish,
                        placeholder: String(localized: "Name Of Dish"),
                        maxLength: 25
                    )
                } header: {
                    Text("New Preset")
                }
                .listRowBackground(Color.chart)

                Section {
                    carbsTextField()
                    if displayFatAndProtein {
                        proteinAndFat()
                    }
                }
                .listRowBackground(Color.chart)

                savePresetButton
            }
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Add Meal Preset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(content: {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onCancel()
                    } label: {
                        Text("Cancel")
                    }
                }
            })
        }
    }

    @ViewBuilder private func carbsTextField() -> some View {
        HStack {
            Text("Carbs").fontWeight(.semibold)
            Spacer()
            TextFieldWithToolBar(
                text: $presetCarbs,
                placeholder: "0",
                keyboardType: .numberPad,
                numberFormatter: mealFormatter
            )
            Text("g").foregroundColor(.secondary)
        }
    }

    @ViewBuilder private func proteinAndFat() -> some View {
        HStack {
            Text("Protein").foregroundColor(.red)
            Spacer()
            TextFieldWithToolBar(
                text: $presetProtein,
                placeholder: "0",
                keyboardType: .numberPad,
                numberFormatter: mealFormatter
            )
            Text("g").foregroundColor(.secondary)
        }
        HStack {
            Text("Fat").foregroundColor(.orange)
            Spacer()
            TextFieldWithToolBar(
                text: $presetFat,
                placeholder: "0",
                keyboardType: .numberPad,
                numberFormatter: mealFormatter
            )
            Text("g").foregroundColor(.secondary)
        }
    }

    private var savePresetButton: some View {
        Button {
            onSave()
        }
        label: {
            Text("Save")
                .font(.headline)
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .listRowBackground(isFormValid ? Color(.systemBlue) : Color(.systemGray))
        .shadow(radius: 3)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .disabled(!isFormValid)
    }
}
