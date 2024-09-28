import CoreData
import Foundation
import Observation
import SwiftUI

struct AddMealPresetView: View {
    @Binding var dish: String
    @Binding var presetCarbs: Decimal
    @Binding var presetFat: Decimal
    @Binding var presetProtein: Decimal
    var onSave: () -> Void
    var onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var color: LinearGradient {
        colorScheme == .dark ? LinearGradient(
            gradient: Gradient(colors: [
                Color.bgDarkBlue,
                Color.bgDarkerDarkBlue
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
            :
            LinearGradient(
                gradient: Gradient(colors: [Color.gray.opacity(0.1)]),
                startPoint: .top,
                endPoint: .bottom
            )
    }

    private var mealFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name Of Dish", text: $dish)
                } header: {
                    Text("New Preset")
                }
                .listRowBackground(Color.chart)

                Section {
                    carbsTextField()
                    proteinAndFat()
                }
                .listRowBackground(Color.chart)

                savePresetButton
            }
            .scrollContentBackground(.hidden).background(color)
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
            Text("Fat").foregroundColor(.orange)
            Spacer()
            TextFieldWithToolBar(text: $presetFat, placeholder: "0", keyboardType: .numberPad, numberFormatter: mealFormatter)
            Text("g").foregroundColor(.secondary)
        }
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
        .listRowBackground(Color(.systemBlue))
        .shadow(radius: 3)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
