import AVFoundation
import SwiftUI
import Swinject

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
                            scannedProductsSection
                            lastScanSection
                            productSection
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
            .navigationTitle(String(localized: "Barcode Scanner"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(content: {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Close"), action: state.hideModal)
                }
            })
            .onAppear {
                configureView()
                state.handleAppear()
            }
        }

        private var header: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Barcode Scanner")
                    .font(.title)
                    .bold()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Scan EAN/UPC barcodes to identify packaged foods.")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }

        @ViewBuilder private func scannerSection(availableHeight: CGFloat) -> some View {
            let hasContent = !state.scannedProducts.isEmpty || state.scannedBarcode != nil || state.product != nil ||
                state.errorMessage != nil
            let minScannerHeight: CGFloat = 200
            let maxScannerHeight: CGFloat = hasContent ? availableHeight * 0.4 : availableHeight * 0.55

            VStack(alignment: .leading, spacing: 0) {
                switch state.cameraStatus {
                case .authorized:
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
                        .frame(height: max(minScannerHeight, maxScannerHeight))

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
