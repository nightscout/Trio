import SwiftUI

// MARK: - Nutrition Editor Sheet

extension BarcodeScanner {
    struct NutritionEditorSheet: View {
        @Bindable var state: StateModel
        @Environment(\.dismiss) private var dismiss

        @State private var name: String = ""
        @State private var calories: String = ""
        @State private var carbohydrates: String = ""
        @State private var sugars: String = ""
        @State private var fat: String = ""
        @State private var protein: String = ""
        @State private var fiber: String = ""
        @State private var servingSize: String = ""

        var body: some View {
            NavigationStack {
                Form {
                    Section(header: Text("Product Name")) {
                        TextField("Name", text: $name)
                    }

                    Section(header: Text("Serving Size")) {
                        HStack {
                            TextField("Amount", text: $servingSize)
                                .keyboardType(.decimalPad)
                            Text("g")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section(header: Text("Nutrition Facts (per 100g)")) {
                        nutritionField(label: "Calories", value: $calories, unit: "kcal")
                        nutritionField(label: "Carbohydrates", value: $carbohydrates, unit: "g")
                        nutritionField(label: "Sugars", value: $sugars, unit: "g")
                        nutritionField(label: "Fat", value: $fat, unit: "g")
                        nutritionField(label: "Protein", value: $protein, unit: "g")
                        nutritionField(label: "Fiber", value: $fiber, unit: "g")
                    }

                    Section {
                        Button {
                            saveAndAdd()
                        } label: {
                            Label("Add to Scanned Products", systemImage: "plus.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                }
                .navigationTitle("Edit Nutrition Data")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
                .onAppear {
                    loadData()
                }
            }
        }

        private func nutritionField(label: String, value: Binding<String>, unit: String) -> some View {
            HStack {
                Text(label)
                Spacer()
                TextField("0", text: value)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text(unit)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .leading)
            }
        }

        private func loadData() {
            name = state.editableNutritionName

            if let data = state.scannedNutritionData {
                calories = data.calories.map { String(format: "%.0f", $0) } ?? ""
                carbohydrates = data.carbohydrates.map { String(format: "%.1f", $0) } ?? ""
                sugars = data.sugars.map { String(format: "%.1f", $0) } ?? ""
                fat = data.fat.map { String(format: "%.1f", $0) } ?? ""
                protein = data.protein.map { String(format: "%.1f", $0) } ?? ""
                fiber = data.fiber.map { String(format: "%.1f", $0) } ?? ""
                servingSize = data.servingSizeGrams.map { String(format: "%.0f", $0) } ?? "100"
            }
        }

        private func saveAndAdd() {
            state.editableNutritionName = name

            state.updateScannedNutritionData(
                calories: Double(calories.replacingOccurrences(of: ",", with: ".")),
                carbohydrates: Double(carbohydrates.replacingOccurrences(of: ",", with: ".")),
                sugars: Double(sugars.replacingOccurrences(of: ",", with: ".")),
                fat: Double(fat.replacingOccurrences(of: ",", with: ".")),
                protein: Double(protein.replacingOccurrences(of: ",", with: ".")),
                fiber: Double(fiber.replacingOccurrences(of: ",", with: ".")),
                servingSizeGrams: Double(servingSize.replacingOccurrences(of: ",", with: "."))
            )

            state.addScannedNutritionLabel()
            dismiss()
        }
    }
}
