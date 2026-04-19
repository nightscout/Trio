import SwiftUI

// MARK: - Nutrition Editor View

extension BarcodeScanner {
    struct NutritionEditorView: View {
        @ObservedObject var state: StateModel
        @FocusState private var focusedField: RootView.NutritionField?
        @Binding var isEditingFromList: Bool
        var onDismissList: () -> Void
        @State private var keyboardIsVisible = false

        @Environment(AppState.self) var appState
        @Environment(\.colorScheme) var colorScheme

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
                                NutritionTextField(
                                    label: String(localized: "Carbohydrates"),
                                    value: Binding(
                                        get: { state.currentScannedItem?.nutriments.carbohydratesPer100g ?? 0 },
                                        set: {
                                            state.updateProductNutriment(keyPath: \.carbohydratesPer100g, value: $0)
                                        }
                                    ),
                                    unit: "g",
                                    field: .carbs,
                                    focusedField: $focusedField
                                )
                                if !state.settingsManager.settings.barcodeScannerOnlyCarbs {
                                    Divider().padding(.leading)

                                    NutritionTextField(
                                        label: String(localized: "Fat"),
                                        value: Binding(
                                            get: { state.currentScannedItem?.nutriments.fatPer100g ?? 0 },
                                            set: { state.updateProductNutriment(keyPath: \.fatPer100g, value: $0) }
                                        ),
                                        unit: "g",
                                        field: .fat,
                                        focusedField: $focusedField
                                    )

                                    Divider().padding(.leading)

                                    NutritionTextField(
                                        label: String(localized: "Protein"),
                                        value: Binding(
                                            get: { state.currentScannedItem?.nutriments.proteinPer100g ?? 0 },
                                            set: { state.updateProductNutriment(keyPath: \.proteinPer100g, value: $0) }
                                        ),
                                        unit: "g",
                                        field: .protein,
                                        focusedField: $focusedField
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

                if !keyboardIsVisible {
                    // Action buttons at bottom
                    VStack(spacing: 12) {
                        if state.hasNutrimentsDivergedFromOriginal,
                           state.hasOpenFoodFactsCredentialsConfigured
                        {
                            if state.isOpenFoodFactsLoggedIn {
                                Menu {
                                    Button {
                                        dismissKeyboard()
                                        state.uploadNutritionCorrectionToOpenFoodFacts()
                                    } label: {
                                        Text(String(localized: "tap to confirm")) // Extra confirmation step to prevent accidental uploads when editing
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        if state.isUploadingCorrection {
                                            ProgressView()
                                                .controlSize(.small)
                                        } else {
                                            Image(systemName: "square.and.arrow.up")
                                        }

                                        Text(String(localized: "Update OpenFoodFactsDB"))
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                }
                                .buttonStyle(.bordered)
                                .tint(Color(red: 128.0 / 255.0, green: 140.0 / 255.0, blue: 235.0 / 255.0))
                                .disabled(!state.canUploadCorrectionToOpenFoodFacts)
                            }

                            if let message = state.correctionUploadMessage, !message.isEmpty {
                                Text(message)
                                    .font(.footnote)
                                    .foregroundStyle(state.correctionUploadSucceeded ? .green : .red)
                            }
                        }

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
                            Label(
                                state.isEditingFromList
                                    ? String(localized: "Update") : String(localized: "Add to List"),
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
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .background(appState.trioBackgroundColor(for: colorScheme).ignoresSafeArea())
            .animation(.easeInOut(duration: 0.2), value: keyboardIsVisible)
            .onReceive(Foundation.NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                keyboardIsVisible = true
                state.isKeyboardVisible = true
                state.isScanning = false
            }
            .onReceive(Foundation.NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardIsVisible = false
                state.isKeyboardVisible = false
            }
            .onChange(of: focusedField) { _, newValue in
                // Pause scanner and hide scanner view when numpad is opened
                if newValue != nil {
                    state.isScanning = false
                    state.isKeyboardVisible = true
                    keyboardIsVisible = true
                } else {
                    state.isKeyboardVisible = false
                    keyboardIsVisible = false
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

                AmountTextField(
                    amount: $state.editingAmount,
                    isMl: $state.editingIsMl,
                    field: .amount,
                    focusedField: $focusedField
                )

                if state.editingIsMl {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            let options: [(String, Double, String)] = [
                                ("0.25l", 250, "l"),
                                ("0.33l", 333, "l"),
                                ("0.5l", 500, "l"),
                                ("1l", 1000, "l")
                            ]
                            ForEach(options, id: \.0) { label, value, unit in
                                let isSelected = state.editingAmount == value
                                Button {
                                    state.selectQuickPortion(amount: value, unit: unit)
                                } label: {
                                    Text(label)
                                        .font(.subheadline.weight(isSelected ? .bold : .medium))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(
                                            isSelected ? Color.blue : Color.secondary.opacity(0.15)
                                        )
                                        .foregroundColor(isSelected ? .white : .primary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Show calculated nutrition based on amount
                if state.editingAmount > 0 {
                    if let product = state.currentScannedItem {
                        let carbsTotal =
                            (product.nutriments.carbohydratesPer100g ?? 0) * state.editingAmount / 100
                        let kcalTotal = (product.nutriments.energyKcalPer100g ?? 0) * state.editingAmount / 100
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

        // MARK: - Helper Functions

        private func dismissKeyboard() {
            focusedField = nil
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
            )
        }
    }
}
