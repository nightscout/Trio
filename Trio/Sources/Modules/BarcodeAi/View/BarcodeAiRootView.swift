import AVFoundation
import SwiftUI
import Swinject

extension BarcodeAi {
    struct RootView: BaseView {
        let resolver: Resolver

        @StateObject var state = StateModel()

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
            .navigationTitle("Barcode AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(content: {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", action: state.hideModal)
                }
            })
            .onAppear {
                configureView()
                state.handleAppear()
            }
        }

        private var header: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Barcode AI")
                    .font(.title)
                    .bold()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Scan EAN/UPC barcodes or use AI image analysis to identify packaged foods.")
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
                                isRunning: $state.isScanning,
                                onDetected: { state.didDetect(barcode: $0) },
                                onFailure: state.reportScannerIssue,
                                onPhotoCaptured: { image in
                                    state.analyzeImageWithGemini(image)
                                },
                                onCoordinatorReady: { coordinator in
                                    state.setCameraCoordinator(coordinator)
                                }
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .strokeBorder(.white.opacity(0.45), lineWidth: 1)
                                    .blendMode(.screen)
                            )
                            .padding(.horizontal)

                            // Overlay when analyzing
                            if state.isAnalyzingImage {
                                Color.black.opacity(0.6)
                                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                    .padding(.horizontal)
                                    .overlay(
                                        VStack(spacing: 12) {
                                            ProgressView()
                                                .scaleEffect(1.5)
                                                .tint(.white)
                                            Text("Analyzing with AI...")
                                                .font(.headline)
                                                .foregroundStyle(.white)
                                        }
                                    )
                            }

                            // Scanning indicator overlay
                            if state.isScanning && !state.isAnalyzingImage {
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

                        // Single row of action buttons
                        HStack(spacing: 12) {
                            // AI Analyze button
                            Button {
                                state.capturePhoto()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkles")
                                    Text("AI Analyze")
                                }
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.tabBar)
                            .disabled(state.isAnalyzingImage)

                            // Resume/Pause scanning button
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
                            .disabled(state.isAnalyzingImage)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                        .padding(.bottom, 8)
                    }
                case .notDetermined:
                    ProgressView("Requesting camera access…")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)
                default:
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Enable camera access to start scanning.", systemImage: "lock.shield")
                            .font(.subheadline)
                        Button("Open Settings", action: state.openAppSettings)
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

                    if !state.scannedProducts.isEmpty {
                        Button {
                            state.openInTreatments()
                        } label: {
                            Label("Use in bolus calculator", systemImage: "arrow.right.circle.fill")
                                .font(.footnote.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }

        @ViewBuilder private var lastScanSection: some View {
            if let barcode = state.scannedBarcode {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Last scanned item", systemImage: "barcode")
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
                ProgressView("Looking up product…")
                    .frame(maxWidth: .infinity)
            } else if let product = state.product {
                ProductDetailsView(product: product, capturedImage: state.lastCapturedImage)
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
    let product: BarcodeAi.OpenFoodFactsProduct
    var capturedImage: UIImage? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                // Priority: 1. Captured image, 2. Product URL image, 3. Placeholder
                if let capturedImage = capturedImage {
                    Image(uiImage: capturedImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else if let imageURL = product.imageURL {
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

private struct ScannedProductRow: View {
    let item: BarcodeAi.ScannedProductItem
    @ObservedObject var state: BarcodeAi.StateModel

    @State private var amountText: String = ""
    @State private var isMlInput: Bool = false
    @State private var showQuickSelector: Bool = false
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                // Priority: 1. Captured image, 2. Product URL image, 3. Placeholder
                if let capturedImage = item.capturedImage {
                    Image(uiImage: capturedImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else if let imageURL = item.product.imageURL {
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
                    "Amount",
                    text: $amountText
                )
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .focused($isTextFieldFocused)
                .onChange(of: amountText) { newValue in
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
                .onChange(of: isMlInput) { newValue in
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
        .onChange(of: item.amount) { _ in
            updateFromItem()
        }
        .onChange(of: item.isMlInput) { _ in
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

private struct NutrimentGrid: View {
    let nutriments: BarcodeAi.OpenFoodFactsProduct.Nutriments

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Per 100g")
                .font(.subheadline.weight(.semibold))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                NutrimentTile(title: "Energy (kcal)", value: nutriments.energyKcalPer100g, unit: "kcal")
                NutrimentTile(title: "Carbs", value: nutriments.carbohydratesPer100g, unit: "g")
                NutrimentTile(title: "Sugars", value: nutriments.sugarsPer100g, unit: "g")
                NutrimentTile(title: "Fat", value: nutriments.fatPer100g, unit: "g")
                NutrimentTile(title: "Protein", value: nutriments.proteinPer100g, unit: "g")
                NutrimentTile(title: "Fiber", value: nutriments.fiberPer100g, unit: "g")
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
    let onPhotoCaptured: (UIImage) -> Void
    let onCoordinatorReady: (BarcodeScannerPreviewCoordinator) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isRunning: $isRunning,
            supportedTypes: supportedTypes,
            onDetected: onDetected,
            onFailure: onFailure,
            onPhotoCaptured: onPhotoCaptured,
            onCoordinatorReady: onCoordinatorReady
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

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate, AVCapturePhotoCaptureDelegate,
        BarcodeScannerPreviewCoordinator
    {
        private var isRunning: Binding<Bool>
        private let supportedTypes: [AVMetadataObject.ObjectType]
        private let onDetected: (String) -> Void
        private let onFailure: (String) -> Void
        private let onPhotoCaptured: (UIImage) -> Void
        private let onCoordinatorReady: (BarcodeScannerPreviewCoordinator) -> Void

        private let session = AVCaptureSession()
        private let metadataOutput = AVCaptureMetadataOutput()
        private var photoOutput: AVCapturePhotoOutput?
        private var captureDevice: AVCaptureDevice?
        private var isConfigured = false
        private var isCaptureInProgress = false

        init(
            isRunning: Binding<Bool>,
            supportedTypes: [AVMetadataObject.ObjectType],
            onDetected: @escaping (String) -> Void,
            onFailure: @escaping (String) -> Void,
            onPhotoCaptured: @escaping (UIImage) -> Void,
            onCoordinatorReady: @escaping (BarcodeScannerPreviewCoordinator) -> Void
        ) {
            self.isRunning = isRunning
            self.supportedTypes = supportedTypes
            self.onDetected = onDetected
            self.onFailure = onFailure
            self.onPhotoCaptured = onPhotoCaptured
            self.onCoordinatorReady = onCoordinatorReady
            super.init()
        }

        func capturePhoto() {
            print("[Camera] capturePhoto() called")
            print("[Camera] photoOutput: \(photoOutput != nil), session.isRunning: \(session.isRunning)")

            guard let photoOutput = photoOutput, session.isRunning else {
                print(
                    "[Camera] ERROR: Camera not ready - photoOutput: \(photoOutput != nil), session.isRunning: \(session.isRunning)"
                )
                DispatchQueue.main.async {
                    self.isCaptureInProgress = false
                    self.onFailure("Camera is not ready. Please wait for the camera to start.")
                }
                return
            }

            print("[Camera] Requesting photo capture...")
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else {
                    print("[Camera] ERROR: self is nil")
                    return
                }

                print("[Camera] Creating photo settings...")
                var settings = AVCapturePhotoSettings()

                // Set photo quality
                settings.isHighResolutionPhotoEnabled = false
                settings.isAutoStillImageStabilizationEnabled = true

                // Configure format if available
                if photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
                    print("[Camera] Setting JPEG format")
                    let format: [String: Any] = [
                        AVVideoCodecKey: AVVideoCodecType.jpeg
                    ]
                    settings = AVCapturePhotoSettings(format: format)
                }

                // Configure flash
                if photoOutput.supportedFlashModes.contains(.off) {
                    settings.flashMode = .off
                }

                print("[Camera] Calling photoOutput.capturePhoto()...")
                photoOutput.capturePhoto(with: settings, delegate: self)
                print("[Camera] capturePhoto() call completed")
            }
        }

        func cleanup() {
            // Stop session on background thread to avoid blocking UI and Fig errors
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

            // Call the callback to let StateModel know the coordinator is ready
            onCoordinatorReady(self)
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
                onFailure("Camera is not available on this device.")
                session.commitConfiguration()
                return
            }

            captureDevice = device

            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input) else {
                    onFailure("Unable to use the back camera.")
                    session.commitConfiguration()
                    return
                }
                session.addInput(input)
            } catch {
                onFailure("Failed to configure camera: \(error.localizedDescription)")
                session.commitConfiguration()
                return
            }

            guard session.canAddOutput(metadataOutput) else {
                onFailure("Unable to read barcodes on this device.")
                session.commitConfiguration()
                return
            }

            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = supportedTypes

            // Add photo output for capturing images
            let photoOutput = AVCapturePhotoOutput()
            if session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
                self.photoOutput = photoOutput
            }

            session.commitConfiguration()
            isConfigured = true
        }

        private func startSession() {
            guard !session.isRunning else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }
        }

        private func stopSession() {
            guard session.isRunning else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.stopRunning()
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

        // MARK: - AVCapturePhotoCaptureDelegate

        func photoOutput(_: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
            print("[Camera] photoOutput:didFinishProcessingPhoto called")
            defer {
                DispatchQueue.main.async {
                    self.isCaptureInProgress = false
                    print("[Camera] Capture in progress reset to false")
                }
            }

            if let error = error {
                print("[Camera] ERROR in photo processing: \(error)")
                DispatchQueue.main.async {
                    self.onFailure("Failed to capture photo: Error code \(error._code) - \(error.localizedDescription)")
                }
                return
            }

            print("[Camera] Photo received, extracting data...")
            // Try multiple ways to get image data
            var imageData: Data?

            // First try: fileDataRepresentation (preferred)
            if let data = photo.fileDataRepresentation() {
                print("[Camera] Using fileDataRepresentation: \(data.count) bytes")
                imageData = data
            }
            // Second try: JPEG representation
            else if let image = UIImage(data: photo.fileDataRepresentation() ?? Data()) {
                print("[Camera] Converting to JPEG")
                imageData = image.jpegData(compressionQuality: 0.8)
            }

            guard let data = imageData, let image = UIImage(data: data) else {
                print("[Camera] ERROR: Unable to create image from data")
                DispatchQueue.main.async {
                    self.onFailure("Failed to convert captured photo to image")
                }
                return
            }

            print("[Camera] Image created: \(image.size)")
            DispatchQueue.main.async {
                print("[Camera] Calling onPhotoCaptured callback")
                self.onPhotoCaptured(image)
            }
        }

        func photoOutput(_: AVCapturePhotoOutput, didFinishCaptureFor _: AVCaptureResolvedPhotoSettings, error: Error?) {
            print("[Camera] photoOutput:didFinishCaptureFor called")
            defer {
                DispatchQueue.main.async {
                    self.isCaptureInProgress = false
                }
            }

            if let error = error {
                print("[Camera] ERROR in capture process: \(error)")
                DispatchQueue.main.async {
                    self.onFailure("Photo capture process failed: Error code \(error._code)")
                }
            } else {
                print("[Camera] Photo capture process completed successfully")
            }
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
