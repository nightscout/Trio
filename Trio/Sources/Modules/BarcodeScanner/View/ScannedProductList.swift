import SwiftUI

// MARK: - Product Details View

extension BarcodeScanner {
    struct ScannedProductRow: View {
        let item: FoodItem
        var state: StateModel
        var focusedItemID: FocusState<UUID?>.Binding

        @State private var amount: Double = 0
        @State private var isMlInput: Bool = false
        @State private var showQuickSelector: Bool = false

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }

        var body: some View {
            let isFocused = focusedItemID.wrappedValue == item.id
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    productImage

                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)

                        if let brand = item.brand {
                            Text(brand)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        KeyboardToolbarTextField(
                            value: $amount,
                            formatter: formatter,
                            configuration: .init(
                                keyboardType: .decimalPad,
                                textAlignment: .left,
                                placeholder: "0",
                                font: .systemFont(ofSize: 17, weight: .bold)
                            ),
                            onFocusContext: { isEntering in
                                if isEntering {
                                    focusedItemID.wrappedValue = item.id
                                } else if isFocused {
                                    focusedItemID.wrappedValue = nil
                                }
                            },
                            externalFocus: isFocused
                        )
                        .frame(width: 70)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onChange(of: amount) { _, newValue in
                            state.updateScannedProductAmount(item, amount: newValue, isMlInput: isMlInput)
                        }
                    }

                    Spacer()

                    Picker("", selection: $isMlInput) {
                        Text("g").tag(false)
                        Text("ml").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 85)
                    .onChange(of: isMlInput) { _, newValue in
                        state.updateScannedProductAmount(item, amount: amount, isMlInput: newValue)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    showQuickSelector.toggle()
                }

                if showQuickSelector {
                    multiplierWheel
                        .padding(.top, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
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
        }

        private func updateFromItem() {
            amount = item.amount
            isMlInput = item.isMlInput
        }

        private func updateAmount(_ amount: Double) {
            guard amount.isFinite else { return }
            self.amount = amount
            state.updateScannedProductAmount(item, amount: amount, isMlInput: isMlInput)
        }

        private func stepMultiplier(by value: Int) {
            let base = item.servingQuantity ?? 100
            let current = base > 0 ? Int(round(item.amount / base)) : 1
            let next = max(1, current + value)
            quickSelectMultiplier(next)
        }

        @ViewBuilder private var multiplierWheel: some View {
            let base = item.servingQuantity ?? 100
            let current = base > 0 ? Int(round(item.amount / base)) : 1

            HStack(spacing: 12) {
                Button {
                    stepMultiplier(by: -1)
                } label: {
                    Image(systemName: "minus")
                        .font(.title2.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)

                VStack(spacing: 2) {
                    Text("\(current)x")
                        .font(.title2.weight(.bold))
                    Text(current == 1 ? String(localized: "Portion") : String(localized: "Portions"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
                .frame(width: 100, height: 60)
                .background(Color.accentColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                Button {
                    stepMultiplier(by: 1)
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
        }

        private func quickSelectMultiplier(_ multiplier: Int) {
            if let servingQuantity = item.servingQuantity, servingQuantity > 0 {
                updateAmount(servingQuantity * Double(multiplier))
            } else {
                updateAmount(Double(multiplier) * 100)
            }
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

    struct ScannedProductsListBody: View {
        @ObservedObject var state: StateModel
        var focusedItemID: FocusState<UUID?>.Binding
        var onEdit: (FoodItem) -> Void

        var body: some View {
            Section {
                if !state.scannedProducts.isEmpty {
                    listHeader
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 0, trailing: 0))
                }

                if state.scannedProducts.isEmpty, state.searchResults.isEmpty, !state.isSearching {
                    emptyListView
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if !state.scannedProducts.isEmpty {
                Section {
                    ForEach(state.scannedProducts) { item in
                        ScannedProductRow(item: item, state: state, focusedItemID: focusedItemID)
                            .listRowInsets(EdgeInsets())
                            .contextMenu {
                                actionButtonsForScannedProduct(for: item)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                actionButtonsForScannedProduct(for: item)
                            }
                            .padding(15)
                    }
                }
                .listRowBackground(Color.chart)
            }
        }

        private func actionButtonsForScannedProduct(for product: FoodItem) -> some View {
            Group {
                Button(role: .destructive) {
                    withAnimation {
                        state.removeScannedProduct(product)
                    }
                } label: {
                    Label(String(localized: "Delete"), systemImage: "trash.fill")
                }
                .tint(.red)

                Button {
                    onEdit(product)
                } label: {
                    Label(String(localized: "Edit"), systemImage: "pencil")
                }
                .tint(.blue)
            }
        }

        private var emptyListView: some View {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                Text(String(localized: "No items yet"))
                    .font(.title3.weight(.medium))
                Text(String(localized: "Scan barcodes or search to add items."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button {
                    state.showListView = false
                } label: {
                    HStack {
                        Image(systemName: "barcode.viewfinder")
                        Text(String(localized: "Start Scanning"))
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }

        private var listHeader: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(
                    "\(state.scannedProducts.count) Item\(state.scannedProducts.count == 1 ? "" : "s")"
                )
                .font(.title2)
                .bold()

                HStack(spacing: 16) {
                    Text("total \(state.scannedCarbs, specifier: "%.1f") g of carbs")
                        .foregroundStyle(.blue)
                }
                .font(.subheadline)
            }
        }
    }
}
