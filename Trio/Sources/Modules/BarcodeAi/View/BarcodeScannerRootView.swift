import AVFoundation
import SwiftUI
import Swinject
import UniformTypeIdentifiers

extension BarcodeScanner {
    struct RootView: BaseView {
        let resolver: Resolver

        @State var state = StateModel()

        @Environment(AppState.self) var appState
        @Environment(\.colorScheme) var colorScheme

        var body: some View {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            header
                            scanModePicker
                            scannedProductsSection

                            if state.scanMode == .barcode {
                                lastScanSection
                                productSection
                            } else {
                                modelStatusSection
                                nutritionLabelSection
                            }

                            errorSection
                        }
                        .padding()
                    }
                    .scrollIndicators(.hidden)
                    .scrollContentBackground(.hidden)

                    scannerSection(availableHeight: geometry.size.height)
                }
            }
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle(
                state
                    .scanMode == .barcode ? String(localized: "Barcode Scanner") : String(localized: "Nutrition Label")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(content: {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Close"), action: state.hideModal)
                }
            })
            .sheet(isPresented: $state.showNutritionEditor) {
                NutritionEditorSheet(state: state)
            }
            .onAppear {
                configureView()
                state.handleAppear()
            }
        }

        private var header: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(state.scanMode == .barcode ? "Barcode Scanner" : "Nutrition Label Scanner")
                    .font(.title)
                    .bold()

                VStack(alignment: .leading, spacing: 6) {
                    if state.scanMode == .barcode {
                        Text("Scan EAN/UPC barcodes to identify packaged foods.")
                    } else {
                        Text("Take a photo of a nutrition label to extract values.")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }

        private var scanModePicker: some View {
            Picker("Scan Mode", selection: Binding(
                get: { state.scanMode },
                set: { state.switchScanMode(to: $0) }
            )) {
                ForEach(ScanMode.allCases, id: \.self) { mode in
                    Label(mode.localizedName, systemImage: mode.icon)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }

        @ViewBuilder private func scannerSection(availableHeight: CGFloat) -> some View {
            let hasContent = !state.scannedProducts.isEmpty || state.scannedBarcode != nil || state.product != nil ||
                state.errorMessage != nil || state.capturedImage != nil
            let minScannerHeight: CGFloat = 200
            let maxScannerHeight: CGFloat = hasContent ? availableHeight * 0.4 : availableHeight * 0.55

            VStack(alignment: .leading, spacing: 0) {
                switch state.cameraStatus {
                case .authorized:
                    if state.scanMode == .barcode {
                        barcodeScannerView(minHeight: minScannerHeight, maxHeight: maxScannerHeight)
                    } else {
                        nutritionLabelScannerView(minHeight: minScannerHeight, maxHeight: maxScannerHeight)
                    }
                case .notDetermined:
                    ProgressView(String(localized: "Requesting camera access…"))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)
                default:
                    VStack(alignment: .leading, spacing: 8) {
                        Label(String(localized: "Enable camera access to start scanning."), systemImage: "lock.shield")
                            .font(.subheadline)
                        Button(String(localized: "Open Settings"), action: state.openAppSettings)
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                }
            }
        }

        @ViewBuilder private func barcodeScannerView(minHeight: CGFloat, maxHeight: CGFloat) -> some View {
            VStack(spacing: 0) {
                ZStack {
                    BarcodeScannerPreview(
                        isRunning: Binding(
                            get: { state.isScanning },
                            set: { state.isScanning = $0 }
                        ),
                        onDetected: { state.didDetect(barcode: $0) },
                        onFailure: state.reportScannerIssue
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(.white.opacity(0.45), lineWidth: 1)
                            .blendMode(.screen)
                    )
                    .padding(.horizontal)

                    // Scanning indicator overlay
                    if state.isScanning {
                        VStack {
                            Spacer()
                            HStack {
                                Image(systemName: "barcode.viewfinder")
                                    .font(.caption)
                                Text("Point at barcode")
                                    .font(.caption)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .padding(.bottom, 12)
                        }
                    }
                }
                .frame(height: max(minHeight, maxHeight))

                // Action buttons
                HStack(spacing: 12) {
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
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.insulin)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .padding(.bottom, 8)
            }
        }

        @ViewBuilder private func nutritionLabelScannerView(minHeight: CGFloat, maxHeight: CGFloat) -> some View {
            VStack(spacing: 0) {
                ZStack {
                    if let capturedImage = state.capturedImage {
                        // Show captured image
                        Image(uiImage: capturedImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .strokeBorder(.white.opacity(0.45), lineWidth: 1)
                                    .blendMode(.screen)
                            )
                            .padding(.horizontal)

                        if state.isProcessingLabel {
                            VStack {
                                ProgressView()
                                    .scaleEffect(1.5)
                                Text("Analyzing nutrition label...")
                                    .font(.caption)
                                    .padding(.top, 8)
                            }
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    } else {
                        // Show placeholder with camera button
                        VStack(spacing: 20) {
                            Image(systemName: "doc.text.viewfinder")
                                .font(.system(size: 60))
                                .foregroundStyle(.secondary)

                            Text("Take a photo of a nutrition label")
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            Button {
                                state.showCameraPicker = true
                            } label: {
                                Label("Open Camera", systemImage: "camera.fill")
                                    .font(.headline)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.insulin)
                            .padding(.horizontal, 40)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(.white.opacity(0.45), lineWidth: 1)
                                .blendMode(.screen)
                        )
                        .padding(.horizontal)
                    }
                }
                .frame(height: max(minHeight, maxHeight))

                // Action buttons
                HStack(spacing: 12) {
                    if state.capturedImage != nil {
                        Button {
                            state.retakePhoto()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Retake")
                            }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.bordered)

                        if state.scannedNutritionData?.hasAnyData == true {
                            Button {
                                state.showNutritionEditor = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "pencil")
                                    Text("Edit & Add")
                                }
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.insulin)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .padding(.bottom, 8)
            }
            .fullScreenCover(isPresented: $state.showCameraPicker) {
                ImagePicker(image: Binding(
                    get: { nil },
                    set: { image in
                        if let image = image {
                            state.didCapturePhoto(image)
                        }
                    }
                ), sourceType: .camera)
                    .ignoresSafeArea()
            }
        }

        @ViewBuilder private var scannedProductsSection: some View {
            if !state.scannedProducts.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Scanned Products")
                        .font(.headline)

                    ForEach(state.scannedProducts) { item in
                        ScannedProductRow(
                            item: item,
                            state: state
                        )
                    }

                    Button {
                        state.openInTreatments()
                    } label: {
                        Label(String(localized: "Use in bolus calculator"), systemImage: "arrow.right.circle.fill")
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }

        @ViewBuilder private var lastScanSection: some View {
            if let barcode = state.scannedBarcode {
                VStack(alignment: .leading, spacing: 8) {
                    Label(String(localized: "Last scanned item"), systemImage: "barcode")
                        .font(.headline)
                    Text(barcode)
                        .font(.system(.body, design: .monospaced))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }

        @ViewBuilder private var productSection: some View {
            if state.isFetchingProduct {
                ProgressView(String(localized: "Looking up product…"))
                    .frame(maxWidth: .infinity)
            } else if let product = state.product {
                ProductDetailsView(product: product)
            }
        }

        // MARK: - Model Status Section

        @ViewBuilder private var modelStatusSection: some View {
            VStack(alignment: .leading, spacing: 12) {
                Label(String(localized: "AI Model"), systemImage: "brain")
                    .font(.headline)

                switch state.modelManager.state {
                case .notDownloaded:
                    modelDownloadView

                case let .downloading(progress):
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Downloading model...")
                                .font(.subheadline)
                            Spacer()
                            Text("\(Int(progress * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: progress)
                            .tint(.insulin)

                        Button("Cancel") {
                            state.modelManager.cancelDownload()
                        }
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                case .downloaded:
                    HStack {
                        Label(String(localized: "Model downloaded"), systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                        Spacer()
                        Button("Load") {
                            state.loadModelIfNeeded()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                case .loading:
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading model...")
                            .font(.subheadline)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                case .ready:
                    HStack {
                        Label(String(localized: "AI Model ready"), systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                        Spacer()

                        Toggle("Use AI", isOn: $state.useAIModel)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Option to delete model
                    Button(role: .destructive) {
                        state.deleteModel()
                    } label: {
                        Label("Delete Model", systemImage: "trash")
                            .font(.caption)
                    }

                case let .error(message):
                    VStack(alignment: .leading, spacing: 8) {
                        Label(String(localized: "Error"), systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button("Retry") {
                            state.modelManager.checkModelStatus()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }

        private var modelDownloadView: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("Import a CoreML nutrition extraction model (.mlpackage, .mlmodelc, .mlmodel, or .zip):")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button {
                        state.showModelFilePicker = true
                    } label: {
                        Label("Select Model File", systemImage: "folder.fill")
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()

                    Text("or use OCR-only mode")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .fileImporter(
                isPresented: $state.showModelFilePicker,
                allowedContentTypes: [.zip, .folder, .data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case let .success(urls):
                    if let url = urls.first {
                        Task {
                            await state.modelManager.importModel(from: url)
                        }
                    }
                case let .failure(error):
                    state.modelManager.state = .error(error.localizedDescription)
                }
            }
        }

        @ViewBuilder private var nutritionLabelSection: some View {
            if let data = state.scannedNutritionData, data.hasAnyData {
                VStack(alignment: .leading, spacing: 12) {
                    Label(String(localized: "Extracted Nutrition Data"), systemImage: "doc.text.magnifyingglass")
                        .font(.headline)

                    VStack(spacing: 8) {
                        if let servingSize = data.servingSize {
                            nutritionRow(label: String(localized: "Serving Size"), value: servingSize)
                        }
                        if let calories = data.calories {
                            nutritionRow(label: String(localized: "Calories"), value: "\(Int(calories)) kcal")
                        }
                        if let carbs = data.carbohydrates {
                            nutritionRow(label: String(localized: "Carbohydrates"), value: String(format: "%.1f g", carbs))
                        }
                        if let sugars = data.sugars {
                            nutritionRow(label: String(localized: "  └ Sugars"), value: String(format: "%.1f g", sugars))
                        }
                        if let fat = data.fat {
                            nutritionRow(label: String(localized: "Fat"), value: String(format: "%.1f g", fat))
                        }
                        if let protein = data.protein {
                            nutritionRow(label: String(localized: "Protein"), value: String(format: "%.1f g", protein))
                        }
                        if let fiber = data.fiber {
                            nutritionRow(label: String(localized: "Fiber"), value: String(format: "%.1f g", fiber))
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            } else if state.isProcessingLabel {
                ProgressView(String(localized: "Analyzing nutrition label…"))
                    .frame(maxWidth: .infinity)
            }
        }

        private func nutritionRow(label: String, value: String) -> some View {
            HStack {
                Text(label)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .fontWeight(.medium)
            }
            .font(.subheadline)
        }

        @ViewBuilder private var errorSection: some View {
            if let message = state.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

// MARK: - Product Details

private struct ProductDetailsView: View {
    let product: BarcodeScanner.OpenFoodFactsProduct

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                if let imageURL = product.imageURL {
                    AsyncImage(url: imageURL) { phase in
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
                } else {
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

// MARK: - Scanned Product Row

private struct ScannedProductRow: View {
    let item: BarcodeScanner.ScannedProductItem
    var state: BarcodeScanner.StateModel

    @State private var amountText: String = ""
    @State private var isMlInput: Bool = false
    @State private var showQuickSelector: Bool = false
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if let imageURL = item.product.imageURL {
                    AsyncImage(url: imageURL) { phase in
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
                } else {
                    placeholder
                        .frame(width: 60, height: 60)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.product.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    if let brand = item.product.brand {
                        Text(brand)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button(role: .destructive) {
                    state.removeScannedProduct(item)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
            }

            HStack(spacing: 12) {
                TextField(
                    String(localized: "Amount"),
                    text: $amountText
                )
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .focused($isTextFieldFocused)
                .onChange(of: amountText) { _, newValue in
                    if let amount = Double(newValue.replacingOccurrences(of: ",", with: ".")) {
                        state.updateScannedProductAmount(item, amount: amount, isMlInput: isMlInput)
                    }
                }

                if isTextFieldFocused {
                    Button {
                        isTextFieldFocused = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.body)
                    }
                    .buttonStyle(.bordered)
                    .transition(.opacity.combined(with: .scale))
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
            .animation(.easeInOut(duration: 0.2), value: isTextFieldFocused)

            // Quick select buttons - shown when tapped
            if showQuickSelector {
                VStack(spacing: 8) {
                    // First row: 1-5
                    HStack(spacing: 8) {
                        ForEach(1 ... 5, id: \.self) { multiplier in
                            Button {
                                if let servingQuantity = item.product.servingQuantity, servingQuantity > 0 {
                                    updateAmount(servingQuantity * Double(multiplier))
                                } else {
                                    updateAmount(Double(multiplier) * 100) // Default to 100g portions
                                }
                                showQuickSelector = false
                            } label: {
                                Text("\(multiplier)x")
                                    .font(.caption.weight(.medium))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    // Second row: 6-10
                    HStack(spacing: 8) {
                        ForEach(6 ... 10, id: \.self) { multiplier in
                            Button {
                                if let servingQuantity = item.product.servingQuantity, servingQuantity > 0 {
                                    updateAmount(servingQuantity * Double(multiplier))
                                } else {
                                    updateAmount(Double(multiplier) * 100) // Default to 100g portions
                                }
                                showQuickSelector = false
                            } label: {
                                Text("\(multiplier)x")
                                    .font(.caption.weight(.medium))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
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
    }

    private func updateFromItem() {
        if item.amount > 0 {
            // Format without decimal if it's a whole number
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
        // Format without decimal if it's a whole number
        if amount.truncatingRemainder(dividingBy: 1) == 0 {
            amountText = String(format: "%.0f", amount)
        } else {
            amountText = String(format: "%.1f", amount)
        }
        state.updateScannedProductAmount(item, amount: amount, isMlInput: isMlInput)
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

// MARK: - Nutriment Grid

private struct NutrimentGrid: View {
    let nutriments: BarcodeScanner.OpenFoodFactsProduct.Nutriments

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Per 100\(nutriments.basis == .per100ml ? "ml" : "g")")
                .font(.subheadline.weight(.semibold))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                NutrimentTile(title: String(localized: "Energy (kcal)"), value: nutriments.energyKcalPer100g, unit: "kcal")
                NutrimentTile(title: String(localized: "Carbs"), value: nutriments.carbohydratesPer100g, unit: "g")
                NutrimentTile(title: String(localized: "Sugars"), value: nutriments.sugarsPer100g, unit: "g")
                NutrimentTile(title: String(localized: "Fat"), value: nutriments.fatPer100g, unit: "g")
                NutrimentTile(title: String(localized: "Protein"), value: nutriments.proteinPer100g, unit: "g")
                NutrimentTile(title: String(localized: "Fiber"), value: nutriments.fiberPer100g, unit: "g")
            }
        }
    }
}

private struct NutrimentTile: View {
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

// MARK: - Scanner Preview

private struct BarcodeScannerPreview: UIViewRepresentable {
    @Binding var isRunning: Bool
    var supportedTypes: [AVMetadataObject.ObjectType] = [.ean13, .ean8, .upce, .code128, .code39]
    let onDetected: (String) -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isRunning: $isRunning,
            supportedTypes: supportedTypes,
            onDetected: onDetected,
            onFailure: onFailure
        )
    }

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_: CameraPreviewView, context: Context) {
        context.coordinator.setRunning(isRunning)
    }

    static func dismantleUIView(_: CameraPreviewView, coordinator: Coordinator) {
        coordinator.cleanup()
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private var isRunning: Binding<Bool>
        private let supportedTypes: [AVMetadataObject.ObjectType]
        private let onDetected: (String) -> Void
        private let onFailure: (String) -> Void

        private let session = AVCaptureSession()
        private let metadataOutput = AVCaptureMetadataOutput()
        private var isConfigured = false

        init(
            isRunning: Binding<Bool>,
            supportedTypes: [AVMetadataObject.ObjectType],
            onDetected: @escaping (String) -> Void,
            onFailure: @escaping (String) -> Void
        ) {
            self.isRunning = isRunning
            self.supportedTypes = supportedTypes
            self.onDetected = onDetected
            self.onFailure = onFailure
            super.init()
        }

        func cleanup() {
            // Stop session on background thread to avoid blocking UI
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self, self.session.isRunning else { return }
                self.session.stopRunning()
            }
        }

        func attach(to view: CameraPreviewView) {
            configureIfNeeded()
            view.videoPreviewLayer.session = session
            view.videoPreviewLayer.videoGravity = .resizeAspectFill
            setRunning(isRunning.wrappedValue)
        }

        func setRunning(_: Bool) {
            guard isConfigured else { return }
            // Always keep the camera session running for preview
            // Only the barcode detection is controlled by the isRunning flag
            if !session.isRunning {
                startSession()
            }
        }

        private func configureIfNeeded() {
            guard !isConfigured else { return }

            session.beginConfiguration()
            session.sessionPreset = .high

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                onFailure(String(localized: "Camera is not available on this device."))
                session.commitConfiguration()
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input) else {
                    onFailure(String(localized: "Unable to use the back camera."))
                    session.commitConfiguration()
                    return
                }
                session.addInput(input)
            } catch {
                onFailure(String(localized: "Failed to configure camera: \(error.localizedDescription)"))
                session.commitConfiguration()
                return
            }

            guard session.canAddOutput(metadataOutput) else {
                onFailure(String(localized: "Unable to read barcodes on this device."))
                session.commitConfiguration()
                return
            }

            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = supportedTypes

            session.commitConfiguration()
            isConfigured = true
        }

        private func startSession() {
            guard !session.isRunning else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }
        }

        func metadataOutput(
            _: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from _: AVCaptureConnection
        ) {
            guard isRunning.wrappedValue else { return }
            guard let readableObject = metadataObjects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject }).first,
                  let stringValue = readableObject.stringValue
            else {
                return
            }

            // Don't stop scanning - the cooldown in StateModel handles rapid scanning prevention
            onDetected(stringValue)
        }
    }
}

private final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

// MARK: - Photo Capture Preview

final class PhotoPreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

extension BarcodeScanner {
    struct PhotoCapturePreview: UIViewRepresentable {
        @Binding var isRunning: Bool
        let onPhotoCaptured: (UIImage) -> Void
        @Binding var captureRequested: Bool

        func makeCoordinator() -> Coordinator {
            Coordinator(
                isRunning: $isRunning,
                onPhotoCaptured: onPhotoCaptured,
                captureRequested: $captureRequested
            )
        }

        func makeUIView(context: Context) -> PhotoPreviewView {
            let view = PhotoPreviewView()
            context.coordinator.attach(to: view)
            return view
        }

        func updateUIView(_: PhotoPreviewView, context: Context) {
            context.coordinator.setRunning(isRunning)

            if captureRequested {
                print("📷 [PhotoCapturePreview] Capture requested")
                context.coordinator.capturePhoto()
                DispatchQueue.main.async {
                    self.captureRequested = false
                }
            }
        }

        static func dismantleUIView(_: PhotoPreviewView, coordinator: Coordinator) {
            coordinator.cleanup()
        }

        final class Coordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
            private var isRunning: Binding<Bool>
            private let onPhotoCaptured: (UIImage) -> Void
            private var captureRequested: Binding<Bool>

            private let session = AVCaptureSession()
            private let videoOutput = AVCaptureVideoDataOutput()
            private var isConfigured = false
            private weak var previewView: PhotoPreviewView?
            private var shouldCaptureNextFrame = false
            private let captureQueue = DispatchQueue(label: "photo.capture.queue")

            init(
                isRunning: Binding<Bool>,
                onPhotoCaptured: @escaping (UIImage) -> Void,
                captureRequested: Binding<Bool>
            ) {
                self.isRunning = isRunning
                self.onPhotoCaptured = onPhotoCaptured
                self.captureRequested = captureRequested
                super.init()
            }

            func cleanup() {
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    guard let self = self, self.session.isRunning else { return }
                    self.session.stopRunning()
                }
            }

            func attach(to view: PhotoPreviewView) {
                previewView = view
                configureIfNeeded()
                view.videoPreviewLayer.session = session
                view.videoPreviewLayer.videoGravity = .resizeAspectFill
                setRunning(isRunning.wrappedValue)
            }

            func setRunning(_ running: Bool) {
                guard isConfigured else { return }
                if running, !session.isRunning {
                    startSession()
                } else if !running, session.isRunning {
                    stopSession()
                }
            }

            private func configureIfNeeded() {
                guard !isConfigured else { return }

                print("📷 [PhotoCapture] Configuring camera session...")

                session.beginConfiguration()
                session.sessionPreset = .photo

                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                    print("❌ [PhotoCapture] Camera not available")
                    session.commitConfiguration()
                    return
                }

                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    guard session.canAddInput(input) else {
                        print("❌ [PhotoCapture] Cannot add camera input")
                        session.commitConfiguration()
                        return
                    }
                    session.addInput(input)
                    print("✅ [PhotoCapture] Camera input added")
                } catch {
                    print("❌ [PhotoCapture] Error: \(error.localizedDescription)")
                    session.commitConfiguration()
                    return
                }

                // Add video output for frame capture
                videoOutput.setSampleBufferDelegate(self, queue: captureQueue)
                videoOutput.alwaysDiscardsLateVideoFrames = true
                videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]

                guard session.canAddOutput(videoOutput) else {
                    print("❌ [PhotoCapture] Cannot add video output")
                    session.commitConfiguration()
                    return
                }

                session.addOutput(videoOutput)

                // Set video orientation to portrait
                if let connection = videoOutput.connection(with: .video) {
                    if connection.isVideoRotationAngleSupported(90) {
                        connection.videoRotationAngle = 90
                    }
                }

                print("✅ [PhotoCapture] Video output added")

                session.commitConfiguration()
                isConfigured = true
                print("✅ [PhotoCapture] Camera configured successfully")
            }

            private func startSession() {
                guard !session.isRunning else {
                    print("📷 [PhotoCapture] Session already running")
                    return
                }
                print("📷 [PhotoCapture] Starting session...")
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    self?.session.startRunning()
                    print("📷 [PhotoCapture] Session started")
                }
            }

            private func stopSession() {
                guard session.isRunning else { return }
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    self?.session.stopRunning()
                }
            }

            func capturePhoto() {
                print("📷 [PhotoCapture] capturePhoto() called")
                print("📷 [PhotoCapture] Session running: \(session.isRunning), configured: \(isConfigured)")

                guard isConfigured else {
                    print("❌ [PhotoCapture] Not configured")
                    return
                }

                guard session.isRunning else {
                    print("⚠️ [PhotoCapture] Session not running, starting and retrying...")
                    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                        self?.session.startRunning()
                        Thread.sleep(forTimeInterval: 0.3)
                        DispatchQueue.main.async {
                            self?.performCapture()
                        }
                    }
                    return
                }

                performCapture()
            }

            private func performCapture() {
                print("📷 [PhotoCapture] performCapture() - requesting next video frame")
                shouldCaptureNextFrame = true
            }

            // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

            func captureOutput(
                _: AVCaptureOutput,
                didOutput sampleBuffer: CMSampleBuffer,
                from _: AVCaptureConnection
            ) {
                guard shouldCaptureNextFrame else { return }
                shouldCaptureNextFrame = false

                print("📷 [PhotoCapture] Capturing video frame...")

                guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                    print("❌ [PhotoCapture] Failed to get image buffer")
                    return
                }

                // Lock the buffer
                CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
                defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }

                let ciImage = CIImage(cvPixelBuffer: imageBuffer)
                let context = CIContext(options: [.useSoftwareRenderer: false])

                // Get the correct orientation
                let width = CVPixelBufferGetWidth(imageBuffer)
                let height = CVPixelBufferGetHeight(imageBuffer)
                print("📷 [PhotoCapture] Buffer size: \(width) x \(height)")

                guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
                    print("❌ [PhotoCapture] Failed to create CGImage")
                    return
                }

                // Create UIImage with correct orientation (portrait)
                let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)

                print("✅ [PhotoCapture] Image captured: \(image.size.width) x \(image.size.height)")

                DispatchQueue.main.async { [weak self] in
                    print("📤 [PhotoCapture] Sending to callback...")
                    self?.onPhotoCaptured(image)
                }
            }
        }
    }
}

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

// MARK: - Image Picker (Camera)

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    var sourceType: UIImagePickerController.SourceType = .camera
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = false

        // Configure for nutrition label scanning
        if sourceType == .camera {
            picker.cameraCaptureMode = .photo
            picker.cameraDevice = .rear
        }

        return picker
    }

    func updateUIViewController(_: UIImagePickerController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(
            _: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                print("📸 [ImagePicker] Image captured: \(image.size.width) x \(image.size.height)")
                parent.image = image
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_: UIImagePickerController) {
            print("📸 [ImagePicker] Cancelled")
            parent.dismiss()
        }
    }
}
