import SwiftUI

// MARK: - Product Details View

extension BarcodeScanner {
    struct ProductDetailsView: View {
        let product: FoodItem

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    switch product.imageSource {
                    case let .url(url):
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case let .success(image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                placeholder
                            default:
                                ProgressView()
                            }
                        }
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    case let .image(uiImage):
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 88, height: 88)
                            .clipShape(RoundedRectangle(cornerRadius: 16))

                    case .none:
                        placeholder
                            .frame(width: 88, height: 88)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(product.name)
                            .font(.headline)
                        if let brand = product.brand {
                            Text(brand)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if let quantity = product.quantity {
                            Text(quantity)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if let serving = product.servingSize {
                            Text("Serving: \(serving)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }

                NutrimentGrid(nutriments: product.nutriments)

                if let ingredients = product.ingredients {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ingredients")
                            .font(.subheadline.weight(.semibold))
                        Text(ingredients)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }

        private var placeholder: some View {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.secondary.opacity(0.2))
                .overlay(
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                )
        }
    }
}

// MARK: - Scanned Product Row

extension BarcodeScanner {
    struct ScannedProductRow: View {
        let item: FoodItem
        var state: StateModel
        var focusedItemID: FocusState<UUID?>.Binding

        @State private var amountText: String = ""
        @State private var isMlInput: Bool = false
        @State private var showQuickSelector: Bool = false

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    productImage

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                        if let brand = item.brand {
                            Text(brand)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }

                HStack(spacing: 12) {
                    TextField(
                        String(localized: "Amount"),
                        text: $amountText
                    )
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .focused(focusedItemID, equals: item.id)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Button {
                                amountText = ""
                                state.updateScannedProductAmount(item, amount: 0, isMlInput: isMlInput)
                            } label: {
                                Image(systemName: "trash")
                            }

                            Spacer()

                            Button {
                                focusedItemID.wrappedValue = nil
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "keyboard.chevron.compact.down")
                                }
                                .font(.headline)
                            }
                        }
                    }
                    .onChange(of: amountText) { _, newValue in
                        if let amount = Double(newValue.replacingOccurrences(of: ",", with: ".")) {
                            if amount.isFinite {
                                state.updateScannedProductAmount(item, amount: amount, isMlInput: isMlInput)
                            }
                        }
                    }

                    Picker("", selection: $isMlInput) {
                        Text("g").tag(false)
                        Text("ml").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 100)
                    .onChange(of: isMlInput) { _, newValue in
                        if let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) {
                            state.updateScannedProductAmount(item, amount: amount, isMlInput: newValue)
                        }
                    }
                }

                if showQuickSelector {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            firstRowButtons
                        }
                        HStack(spacing: 8) {
                            secondRowButtons
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showQuickSelector.toggle()
                }
            }
            .onAppear {
                updateFromItem()
            }
            .onChange(of: item.amount) { _, _ in
                updateFromItem()
            }
            .onChange(of: item.isMlInput) { _, _ in
                updateFromItem()
            }
            .onChange(of: focusedItemID.wrappedValue) { _, newValue in
                // Pause scanner and hide scanner view when numpad is opened
                if newValue == item.id {
                    // handled in parent now
                }
            }
        }

        private func updateFromItem() {
            if item.amount > 0 {
                if item.amount.truncatingRemainder(dividingBy: 1) == 0 {
                    amountText = String(format: "%.0f", item.amount)
                } else {
                    amountText = String(format: "%.1f", item.amount)
                }
            } else {
                amountText = ""
            }
            isMlInput = item.isMlInput
        }

        private func updateAmount(_ amount: Double) {
            guard amount.isFinite else { return }

            if amount.truncatingRemainder(dividingBy: 1) == 0 {
                amountText = String(format: "%.0f", amount)
            } else {
                amountText = String(format: "%.1f", amount)
            }
            state.updateScannedProductAmount(item, amount: amount, isMlInput: isMlInput)
        }

        @ViewBuilder private var firstRowButtons: some View {
            ForEach(1 ... 5, id: \.self) { multiplier in
                Button {
                    quickSelectMultiplier(multiplier)
                } label: {
                    Text("\(multiplier)x")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }

        @ViewBuilder private var secondRowButtons: some View {
            ForEach(6 ... 10, id: \.self) { multiplier in
                Button {
                    quickSelectMultiplier(multiplier)
                } label: {
                    Text("\(multiplier)x")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }

        private func quickSelectMultiplier(_ multiplier: Int) {
            if let servingQuantity = item.servingQuantity, servingQuantity > 0 {
                updateAmount(servingQuantity * Double(multiplier))
            } else {
                updateAmount(Double(multiplier) * 100)
            }
            showQuickSelector = false
        }

        @ViewBuilder private var productImage: some View {
            switch item.imageSource {
            case let .image(uiImage):
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

            case let .url(url):
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    default:
                        ProgressView()
                    }
                }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            case .none:
                placeholder
                    .frame(width: 60, height: 60)
            }
        }

        private var placeholder: some View {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.2))
                .overlay(
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                )
        }
    }
}

// MARK: - Nutriment Grid

extension BarcodeScanner {
    struct NutrimentGrid: View {
        let nutriments: FoodItem.Nutriments

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Per 100\(nutriments.basis == .per100ml ? "ml" : "g")")
                    .font(.subheadline.weight(.semibold))

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12
                ) {
                    NutrimentTile(
                        title: String(localized: "Energy (kcal)"), value: nutriments.energyKcalPer100g,
                        unit: "kcal"
                    )
                    NutrimentTile(
                        title: String(localized: "Carbs"), value: nutriments.carbohydratesPer100g, unit: "g"
                    )
                    NutrimentTile(
                        title: String(localized: "Sugars"), value: nutriments.sugarsPer100g, unit: "g"
                    )
                    NutrimentTile(title: String(localized: "Fat"), value: nutriments.fatPer100g, unit: "g")
                    NutrimentTile(
                        title: String(localized: "Protein"), value: nutriments.proteinPer100g, unit: "g"
                    )
                    NutrimentTile(
                        title: String(localized: "Fiber"), value: nutriments.fiberPer100g, unit: "g"
                    )
                }
            }
        }
    }

    struct NutrimentTile: View {
        let title: String
        let value: Double?
        let unit: String

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formattedValue)
                    .font(.headline)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }

        private var formattedValue: String {
            guard let value else { return "—" }
            return "\(String(format: "%.1f", value)) \(unit)"
        }
    }
}
