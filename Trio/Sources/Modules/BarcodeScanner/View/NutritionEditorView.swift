import SwiftUI

// MARK: - Nutrition Editor View

extension BarcodeScanner {
    struct NutritionEditorView: View {
        @ObservedObject var state: StateModel
        var focusedField: FocusState<RootView.NutritionField?>.Binding
        @Binding var isEditingFromList: Bool
        var onDismissList: () -> Void

        var body: some View {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let product = state.currentScannedItem {
                            // Product header
                            HStack(alignment: .top, spacing: 12) {
                                switch product.imageSource {
                                case let .url(url):
                                    AsyncImage(url: url) { phase in
                                        switch phase {
                                        case let .success(image):
                                            image
                                                .resizable()
                                                .scaledToFill()
                                        case .failure:
                                            productPlaceholder
                                        default:
                                            ProgressView()
                                        }
                                    }
                                    .frame(width: 70, height: 70)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))

                                case let .image(uiImage):
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 70, height: 70)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))

                                case .none:
                                    productPlaceholder
                                        .frame(width: 70, height: 70)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(product.name)
                                        .font(.headline)
                                        .lineLimit(2)
                                    if let brand = product.brand {
                                        Text(brand)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let quantity = product.quantity {
                                        Text(quantity)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }

                            Text("Nutrition (per 100g)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)

                            // Editable nutrition rows for product
                            VStack(spacing: 0) {
                                editableProductNutritionRow(
                                    label: String(localized: "Carbohydrates"),
                                    keyPath: \.carbohydratesPer100g,
                                    unit: "g",
                                    field: .carbs
                                )
                                if !state.settingsManager.settings.barcodeScannerOnlyCarbs {
                                    Divider().padding(.leading)

                                    editableProductNutritionRow(
                                        label: String(localized: "Fat"),
                                        keyPath: \.fatPer100g,
                                        unit: "g",
                                        field: .fat
                                    )

                                    Divider().padding(.leading)

                                    editableProductNutritionRow(
                                        label: String(localized: "Protein"),
                                        keyPath: \.proteinPer100g,
                                        unit: "g",
                                        field: .protein
                                    )
                                }
                            }
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                            // Amount input section
                            amountInputSection
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollIndicators(.hidden)

                // Action buttons at bottom
                VStack(spacing: 12) {
                    // Add & Continue button
                    Button {
                        dismissKeyboard()
                        if state.currentScannedItem != nil {
                            state.addProductToList()
                        }

                        if isEditingFromList {
                            isEditingFromList = false
                            onDismissList()
                        }
                    } label: {
                        Label(String(localized: "Add to List"), systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.insulin)

                    Button {
                        dismissKeyboard()
                        state.cancelEditing()

                        if isEditingFromList {
                            isEditingFromList = false
                            onDismissList()
                        }
                    } label: {
                        Text("Cancel")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
                .padding(.top, 8)
            }
        }

        // MARK: - Helper Views

        private var amountInputSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Amount you're eating")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        TextField(
                            "0",
                            value: $state.editingAmount,
                            format: .number.precision(.fractionLength(0 ... 1))
                        )
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.title2.weight(.semibold))
                        .frame(width: 100)
                        .focused(focusedField, equals: .amount)

                        Text(state.editingIsMl ? "ml" : "g")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Unit toggle
                    Picker("Unit", selection: $state.editingIsMl) {
                        Text("g").tag(false)
                        Text("ml").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 100)
                }

                // Show calculated nutrition based on amount
                if state.editingAmount > 0 {
                    if let product = state.currentScannedItem {
                        let carbsTotal = (product.nutriments.carbohydratesPer100g ?? 0) * state.editingAmount / 100
                        let kcalTotal = (product.nutriments.energyKcalPer100g ?? 0) * state.editingAmount / 100
                        nutritionSummary(carbs: carbsTotal, kcal: kcalTotal)
                    } else if let data = state.scannedNutritionData {
                        let carbsTotal = (data.carbohydrates ?? 0) * state.editingAmount / 100
                        let kcalTotal = (data.calories ?? 0) * state.editingAmount / 100
                        nutritionSummary(carbs: carbsTotal, kcal: kcalTotal)
                    }
                }
            }
        }

        private func nutritionSummary(carbs: Double, kcal _: Double) -> some View {
            HStack(spacing: 16) {
                Text("total \(carbs, specifier: "%.1f") g of carbs")
                    .foregroundStyle(.blue)
            }
            .font(.caption)
            .padding(.top, 4)
        }

        private var productPlaceholder: some View {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.2))
                .overlay(
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                )
        }

        private func editableProductNutritionRow(
            label: String,
            keyPath: WritableKeyPath<FoodItem.Nutriments, Double?>,
            unit: String,
            field: RootView.NutritionField
        ) -> some View {
            let isFocused = focusedField.wrappedValue == field
            return HStack {
                Text(label)
                    .foregroundStyle(isFocused ? .primary : .secondary)
                    .font(.subheadline.weight(isFocused ? .semibold : .regular))
                Spacer()
                HStack(spacing: 4) {
                    TextField(
                        "0",
                        value: Binding(
                            get: { state.currentScannedItem?.nutriments[keyPath: keyPath] },
                            set: { newValue in
                                state.updateProductNutriment(keyPath: keyPath, value: newValue)
                            }
                        ),
                        format: .number.precision(.fractionLength(0 ... 1))
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                    .focused(focusedField, equals: field)

                    Text(unit)
                        .foregroundStyle(.secondary)
                        .frame(width: 35, alignment: .leading)
                }
                .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture {
                focusedField.wrappedValue = field
            }
            .background(isFocused ? Color.accentColor.opacity(0.1) : Color.clear)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
        }

        private func editableNutritionRow(
            label: String,
            value: Binding<Double?>,
            unit: String,
            field: RootView.NutritionField
        ) -> some View {
            let isFocused = focusedField.wrappedValue == field
            return HStack {
                Text(label)
                    .foregroundStyle(isFocused ? .primary : .secondary)
                    .font(.subheadline.weight(isFocused ? .semibold : .regular))
                Spacer()
                HStack(spacing: 4) {
                    TextField(
                        "0",
                        value: value,
                        format: .number.precision(.fractionLength(0 ... 1))
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                    .focused(focusedField, equals: field)

                    Text(unit)
                        .foregroundStyle(.secondary)
                        .frame(width: 35, alignment: .leading)
                }
                .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(isFocused ? Color.accentColor.opacity(0.1) : Color.clear)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
        }

        // MARK: - Helper Functions

        private func dismissKeyboard() {
            focusedField.wrappedValue = nil
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}
