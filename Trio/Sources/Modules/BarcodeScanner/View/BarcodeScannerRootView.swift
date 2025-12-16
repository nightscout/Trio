import SwiftUI
import Swinject

// MARK: - Root View

extension BarcodeScanner {
    struct RootView: BaseView {
        let resolver: Resolver

        @StateObject var state = StateModel()

        @State private var showListView = false
        @State private var isEditingFromList = false

        @Environment(AppState.self) var appState
        @Environment(\.colorScheme) var colorScheme
        @FocusState private var focusedField: NutritionField?

        enum NutritionField: Hashable {
            case name
            case amount
            case calories
            case carbs
            case sugars
            case fat
            case protein
            case fiber
        }

        var body: some View {
            ZStack {
                if showListView {
                    listViewContent
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    scannerViewContent
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showListView)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle(String(localized: showListView ? "Scanned Items" : "Food Scanner"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if showListView {
                        Button {
                            showListView = false
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Scanner")
                            }
                        }
                    } else {
                        Button(String(localized: "Close"), action: state.hideModal)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !showListView {
                        Button {
                            showListView = true
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "list.bullet")
                                    .font(.body)
                                if !state.scannedProducts.isEmpty {
                                    Text("\(state.scannedProducts.count)")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white)
                                        .padding(4)
                                        .background(Circle().fill(Color.red))
                                        .offset(x: 8, y: -8)
                                }
                            }
                        }
                    }
                }
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button(String(localized: "Done")) {
                            dismissKeyboard()
                        }
                    }
                }
            }
            .onAppear {
                configureView()
                state.handleAppear()
            }
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

        /// Whether to show the editor view (product or nutrition data available)
        private var showEditorView: Bool {
            state.currentScannedItem != nil || state.scannedNutritionData != nil
        }

        // MARK: - Scanner View Content

        private var scannerViewContent: some View {
            ZStack {
                if state.isFetchingProduct || state.isProcessingLabel {
                    // Loading state
                    loadingView
                        .transition(.opacity)
                } else if showEditorView {
                    // Show full editor view when product/nutrition data is available
                    nutritionEditorView
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    // Scanner view
                    fullScreenCameraView
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                // Error overlay (always visible if there's an error)
                if let message = state.errorMessage, !showEditorView {
                    VStack {
                        Spacer()
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .padding(12)
                            .background(Color.orange.opacity(0.12))
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal)
                            .padding(.bottom, 100)
                    }
                    .allowsHitTesting(false)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showEditorView)
            .animation(.easeInOut(duration: 0.2), value: state.isFetchingProduct)
            .animation(.easeInOut(duration: 0.2), value: state.isProcessingLabel)
        }

        // MARK: - Loading View

        private var loadingView: some View {
            VStack(spacing: 16) {
                Spacer()
                ProgressView()
                    .scaleEffect(1.5)
                Text(
                    state
                        .isFetchingProduct ? String(localized: "Looking up product…") :
                        String(localized: "Analyzing nutrition label…")
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        // MARK: - Nutrition Editor View (Full Screen)

        private var nutritionEditorView: some View {
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
                                    label: String(localized: "Calories"),
                                    keyPath: \.energyKcalPer100g,
                                    unit: "kcal",
                                    field: .calories
                                )

                                Divider().padding(.leading)

                                editableProductNutritionRow(
                                    label: String(localized: "Carbohydrates"),
                                    keyPath: \.carbohydratesPer100g,
                                    unit: "g",
                                    field: .carbs
                                )

                                Divider().padding(.leading)

                                editableProductNutritionRow(
                                    label: String(localized: "  └ Sugars"),
                                    keyPath: \.sugarsPer100g,
                                    unit: "g",
                                    field: .sugars
                                )

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

                                Divider().padding(.leading)

                                editableProductNutritionRow(
                                    label: String(localized: "Fiber"),
                                    keyPath: \.fiberPer100g,
                                    unit: "g",
                                    field: .fiber
                                )
                            }
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                            // Amount input section
                            amountInputSection

                        } else if state.scannedNutritionData != nil {
                            HStack {
                                Image(systemName: "doc.text.magnifyingglass")
                                TextField("Product Name", text: $state.editableNutritionName)
                                    .focused($focusedField, equals: .name)
                                    .submitLabel(.done)
                            }
                            .font(.headline)

                            HStack(spacing: 4) {
                                Text("Values per")
                                TextField("100", value: $state.scannedLabelBasisAmount, format: .number)
                                    .font(.subheadline.weight(.semibold))
                                    .multilineTextAlignment(.center)
                                    .keyboardType(.decimalPad)
                                    .frame(width: 50)
                                    .padding(.horizontal, 4)
                                    .background(Color.secondary.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                Text("g")
                                Spacer()
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)

                            VStack(spacing: 0) {
                                editableNutritionRow(
                                    label: String(localized: "Calories"),
                                    value: Binding(
                                        get: { state.scannedNutritionData?.calories },
                                        set: { state.scannedNutritionData?.calories = $0 }
                                    ),
                                    unit: "kcal",
                                    field: .calories
                                )

                                Divider().padding(.leading)

                                editableNutritionRow(
                                    label: String(localized: "Carbohydrates"),
                                    value: Binding(
                                        get: { state.scannedNutritionData?.carbohydrates },
                                        set: { state.scannedNutritionData?.carbohydrates = $0 }
                                    ),
                                    unit: "g",
                                    field: .carbs
                                )

                                Divider().padding(.leading)

                                editableNutritionRow(
                                    label: String(localized: "  └ Sugars"),
                                    value: Binding(
                                        get: { state.scannedNutritionData?.sugars },
                                        set: { state.scannedNutritionData?.sugars = $0 }
                                    ),
                                    unit: "g",
                                    field: .sugars
                                )

                                Divider().padding(.leading)

                                editableNutritionRow(
                                    label: String(localized: "Fat"),
                                    value: Binding(
                                        get: { state.scannedNutritionData?.fat },
                                        set: { state.scannedNutritionData?.fat = $0 }
                                    ),
                                    unit: "g",
                                    field: .fat
                                )

                                Divider().padding(.leading)

                                editableNutritionRow(
                                    label: String(localized: "Protein"),
                                    value: Binding(
                                        get: { state.scannedNutritionData?.protein },
                                        set: { state.scannedNutritionData?.protein = $0 }
                                    ),
                                    unit: "g",
                                    field: .protein
                                )

                                Divider().padding(.leading)

                                editableNutritionRow(
                                    label: String(localized: "Fiber"),
                                    value: Binding(
                                        get: { state.scannedNutritionData?.fiber },
                                        set: { state.scannedNutritionData?.fiber = $0 }
                                    ),
                                    unit: "g",
                                    field: .fiber
                                )
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
                            showListView = true
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
                            showListView = true
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

        // MARK: - Full Screen Camera View

        private var fullScreenCameraView: some View {
            ZStack {
                switch state.cameraStatus {
                case .authorized:
                    ZStack {
                        if let capturedImage = state.capturedImage {
                            Image(uiImage: capturedImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                                )
                                .padding(.horizontal)
                                .padding(.top, 8)
                        } else {
                            ScannerPreviewView(
                                isRunning: Binding(
                                    get: { state.isScanning },
                                    set: { state.isScanning = $0 }
                                ),
                                onDetected: { state.didDetect(barcode: $0) },
                                onFailure: state.reportScannerIssue,
                                onFrameCaptured: { state.lastCameraFrame = $0 }
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                            )
                            .padding(.horizontal)
                            .padding(.top, 8)
                            .padding(.bottom, 120)

                            // Scanning indicator
                            VStack {
                                Spacer()
                                HStack {
                                    if state.isScanning {
                                        Image(systemName: "barcode.viewfinder")
                                            .font(.caption)
                                        Text("Scanning barcodes...")
                                            .font(.caption)
                                    } else {
                                        Image(systemName: "pause.fill")
                                            .font(.caption)
                                        Text("Paused")
                                            .font(.caption)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .padding(.bottom, 140)
                            }
                        }

                        // Action buttons at bottom
                        VStack {
                            Spacer()
                            cameraActionButtons
                        }
                    }

                case .notDetermined:
                    VStack {
                        Spacer()
                        ProgressView(String(localized: "Requesting camera access…"))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)

                default:
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "camera.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.secondary)
                        Label(String(localized: "Enable camera access to start scanning."), systemImage: "lock.shield")
                            .font(.subheadline)
                        Button(String(localized: "Open Settings"), action: state.openAppSettings)
                            .buttonStyle(.borderedProminent)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.9))
                }
            }
        }

        // MARK: - Camera Action Buttons

        private var cameraActionButtons: some View {
            HStack(spacing: 12) {
                if state.capturedImage != nil {
                    Button {
                        state.clearCapturedImage()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "camera")
                            Text("Back")
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.insulin)
                } else {
                    Button {
                        if state.isScanning {
                            state.isScanning = false
                        } else {
                            state.scanAgain(resetResults: false)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: state.isScanning ? "pause.fill" : "barcode.viewfinder")
                            Text(state.isScanning ? "Pause" : "Scan")
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(state.isScanning ? .orange : .insulin)

                    if !state.scannedProducts.isEmpty {
                        Button {
                            state.openInTreatments()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.right.circle.fill")
                                Text("Calculator")
                            }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 16)
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
                        .focused($focusedField, equals: .amount)

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

        private func nutritionSummary(carbs: Double, kcal: Double) -> some View {
            HStack(spacing: 16) {
                Label("\(carbs, specifier: "%.1f") g carbs", systemImage: "leaf.fill")
                    .foregroundStyle(.green)
                Label("\(kcal, specifier: "%.0f") kcal", systemImage: "flame.fill")
                    .foregroundStyle(.orange)
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
            field: NutritionField
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

        // MARK: - List View Content

        private var listViewContent: some View {
            VStack(spacing: 0) {
                if state.scannedProducts.isEmpty {
                    emptyListView
                } else {
                    List {
                        Section {
                            listHeader
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 8, trailing: 16))
                        }

                        Section {
                            ForEach(state.scannedProducts) { item in
                                ScannedProductRow(item: item, state: state)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            withAnimation {
                                                state.removeScannedProduct(item)
                                            }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                        .tint(.red)
                                    }
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button {
                                            state.editScannedProduct(item)
                                            isEditingFromList = true
                                            showListView = false
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        .tint(.blue)
                                    }
                            }
                        }

                        Section {
                            Button {
                                state.openInTreatments()
                            } label: {
                                Label(String(localized: "Use in bolus calculator"), systemImage: "arrow.right.circle.fill")
                                    .font(.footnote.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 32, trailing: 16))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }

        private var emptyListView: some View {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                Text("No items scanned yet")
                    .font(.title3.weight(.medium))
                Text("Scan barcodes or nutrition labels to add items here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    showListView = false
                } label: {
                    Label("Start Scanning", systemImage: "barcode.viewfinder")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
                Spacer()
            }
            .padding()
        }

        private var listHeader: some View {
            let totalCarbs = state.scannedProducts.reduce(into: 0.0) { result, item in
                let carbsPer100 = item.nutriments.carbohydratesPer100g ?? 0
                let amount = item.amount.isFinite ? item.amount : 0
                result += (carbsPer100 * amount) / 100.0
            }
            let totalCalories = state.scannedProducts.reduce(into: 0.0) { result, item in
                let kcalPer100 = item.nutriments.energyKcalPer100g ?? 0
                let amount = item.amount.isFinite ? item.amount : 0
                result += (kcalPer100 * amount) / 100.0
            }

            return VStack(alignment: .leading, spacing: 8) {
                Text("\(state.scannedProducts.count) Item\(state.scannedProducts.count == 1 ? "" : "s") Scanned")
                    .font(.title2)
                    .bold()

                HStack(spacing: 16) {
                    Label("\(totalCarbs, specifier: "%.1f") g carbs", systemImage: "leaf.fill")
                        .foregroundStyle(.green)
                    Label("\(totalCalories, specifier: "%.0f") kcal", systemImage: "flame.fill")
                        .foregroundStyle(.orange)
                }
                .font(.subheadline)
            }
        }

        // MARK: - Helper Functions

        private func dismissKeyboard() {
            focusedField = nil
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }

        private func editableNutritionRow(
            label: String,
            value: Binding<Double?>,
            unit: String,
            field: NutritionField
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
    }
}
