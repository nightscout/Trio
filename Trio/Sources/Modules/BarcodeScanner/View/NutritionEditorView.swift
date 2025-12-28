import SwiftUI

// MARK: - Nutrition Editor View

extension BarcodeScanner {
    struct NutritionEditorView: View {
        @ObservedObject var state: StateModel
        @FocusState private var focusedField: RootView.NutritionField?
        @Binding var isEditingFromList: Bool
        var onDismissList: () -> Void

        @Environment(AppState.self) var appState
        @Environment(\.colorScheme) var colorScheme

        @State private var editingAmountText: String = ""

        var body: some View {
            ZStack(alignment: .bottom) {
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
                                    ProductNutritionRow(
                                        label: String(localized: "Carbohydrates"),
                                        keyPath: \.carbohydratesPer100g,
                                        unit: "g",
                                        field: .carbs,
                                        focusedField: $focusedField,
                                        state: state
                                    )
                                    if !state.settingsManager.settings.barcodeScannerOnlyCarbs {
                                        Divider().padding(.leading)

                                        ProductNutritionRow(
                                            label: String(localized: "Fat"),
                                            keyPath: \.fatPer100g,
                                            unit: "g",
                                            field: .fat,
                                            focusedField: $focusedField,
                                            state: state
                                        )

                                        Divider().padding(.leading)

                                        ProductNutritionRow(
                                            label: String(localized: "Protein"),
                                            keyPath: \.proteinPer100g,
                                            unit: "g",
                                            field: .protein,
                                            focusedField: $focusedField,
                                            state: state
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
                        // Add bottom padding to allow scrolling past the toolbar
                        .padding(.bottom, focusedField != nil ? 50 : 0)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .scrollIndicators(.hidden)
                    .onChange(of: state.editingAmount) { newValue in
                        let formatter = NumberFormatter()
                        formatter.locale = Locale.current
                        formatter.numberStyle = .decimal
                        formatter.maximumFractionDigits = 1
                        if newValue == 0 {
                            editingAmountText = ""
                        } else {
                            editingAmountText = formatter.string(from: NSNumber(value: newValue)) ?? String(newValue)
                        }
                    }

                    // Action buttons at bottom
                    VStack(spacing: 12) {
                        // Add & Continue button
                        Button {
                            dismissKeyboard()
                            if state.currentScannedItem != nil {
                                // Ensure latest edited amount is applied (parse comma/dot)
                                if let parsed = parseAmount(from: editingAmountText) {
                                    state.editingAmount = parsed
                                }
                                state.addProductToList()
                            }

                            if isEditingFromList {
                                isEditingFromList = false
                                onDismissList()
                            }
                        } label: {
                            Label(
                                state.isEditingFromList ? String(localized: "Update") : String(localized: "Add to List"),
                                systemImage: "plus.circle.fill"
                            )
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

                // Custom Keyboard Toolbar (Manual Implementation)
                if focusedField != nil {
                    customKeyboardToolbar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .background(appState.trioBackgroundColor(for: colorScheme).ignoresSafeArea())
            .onChange(of: focusedField) { _, newValue in
                // Pause scanner and hide scanner view when numpad is opened
                if newValue != nil {
                    state.isScanning = false
                    state.isKeyboardVisible = true
                } else {
                    state.isKeyboardVisible = false
                }
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
                            text: $editingAmountText
                        )
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.title2.weight(.semibold))
                        .frame(minWidth: 110, maxWidth: 140)
                        .focused($focusedField, equals: .amount)
                        .onChange(of: editingAmountText) { newValue in
                            // Accept both comma and dot decimal separators and update the numeric model
                            if newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                                state.editingAmount = 0
                            } else if let parsed = parseAmount(from: newValue) {
                                state.editingAmount = parsed
                            }
                        }

                        Text(state.editingIsMl ? "ml" : "g")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 6)
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
                    }
                }
            }
            .onAppear {
                let formatter = NumberFormatter()
                formatter.locale = Locale.current
                formatter.numberStyle = .decimal
                formatter.maximumFractionDigits = 1
                if state.editingAmount == 0 {
                    editingAmountText = ""
                } else {
                    editingAmountText = formatter
                        .string(from: NSNumber(value: state.editingAmount)) ?? String(state.editingAmount)
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

        /// Parse a user-entered amount string that may use comma or dot as decimal separator
        private func parseAmount(from text: String) -> Double? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }

            // Try direct Double parsing with replacing comma -> dot
            let dotted = trimmed.replacingOccurrences(of: ",", with: ".")
            if let d = Double(dotted) {
                return d
            }

            // Fallback to NumberFormatter with locale
            let formatter = NumberFormatter()
            formatter.locale = Locale.current
            formatter.numberStyle = .decimal
            if let num = formatter.number(from: trimmed) {
                return num.doubleValue
            }

            return nil
        }

        private var productPlaceholder: some View {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.2))
                .overlay(
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                )
        }

        struct ProductNutritionRow: View {
            let label: String
            let keyPath: WritableKeyPath<FoodItem.Nutriments, Double?>
            let unit: String
            let field: RootView.NutritionField
            var focusedField: FocusState<RootView.NutritionField?>.Binding
            @ObservedObject var state: StateModel

            @State private var text: String = ""

            var body: some View {
                let isFocused = focusedField.wrappedValue == field
                ZStack {
                    TextField(
                        "0",
                        text: $text
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused(focusedField, equals: field)
                    .accentColor(.accentColor)
                    .padding(.horizontal)
                    // Add extra trailing padding to avoid overlapping with unit "g"
                    .padding(.trailing, 25)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
                    .frame(maxWidth: .infinity)
                    .onChange(of: text) { newValue in
                        // Handle comma/dot and update model
                        guard !newValue.isEmpty else {
                            state.updateProductNutriment(keyPath: keyPath, value: 0)
                            return
                        }

                        let standardized = newValue.replacingOccurrences(of: ",", with: ".")
                        if let value = Double(standardized) {
                            state.updateProductNutriment(keyPath: keyPath, value: value)
                        }
                    }
                    .onChange(of: isFocused) { focused in
                        if focused {
                            // On focus, sync text from model
                            if let val = state.currentScannedItem?.nutriments[keyPath: keyPath], val > 0 {
                                let formatter = NumberFormatter()
                                formatter.numberStyle = .decimal
                                formatter.maximumFractionDigits = 1
                                text = formatter.string(from: NSNumber(value: val)) ?? String(val)
                            } else {
                                text = ""
                            }
                        }
                    }
                    .onAppear {
                        // Initial sync
                        if let val = state.currentScannedItem?.nutriments[keyPath: keyPath], val > 0 {
                            let formatter = NumberFormatter()
                            formatter.numberStyle = .decimal
                            formatter.maximumFractionDigits = 1
                            text = formatter.string(from: NSNumber(value: val)) ?? String(val)
                        }
                    }

                    // Overlays: label (left) and unit (right) — don't intercept taps
                    HStack {
                        Text(label)
                            .foregroundStyle(isFocused ? .primary : .secondary)
                            .font(.subheadline.weight(isFocused ? .semibold : .regular))
                            .allowsHitTesting(false)
                        Spacer()
                        Text(unit)
                            .foregroundStyle(.secondary)
                            .frame(width: 20, alignment: .trailing)
                            .allowsHitTesting(false)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
                .background(isFocused ? Color.accentColor.opacity(0.15) : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture {
                    focusedField.wrappedValue = field
                }
                .animation(.easeInOut(duration: 0.15), value: isFocused)
            }
        }

        private func editableNutritionRow(
            label: String,
            value: Binding<Double?>,
            unit: String,
            field: RootView.NutritionField
        ) -> some View {
            let isFocused = focusedField == field
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
                    .focused($focusedField, equals: field)

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
            focusedField = nil
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }

        private var customKeyboardToolbar: some View {
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Spacer()
                    Button {
                        dismissKeyboard()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "keyboard.chevron.compact.down")
                            Text("Done")
                        }
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Color(uiColor: .secondarySystemBackground))
            }
        }
    }
}
