import SwiftUI
import Swinject

// MARK: - Root View

extension BarcodeScanner {
    struct RootView: BaseView {
        let resolver: Resolver
        var showListInitially: Bool = false
        var onAddTreatments: ((Decimal, Decimal, Decimal, String) -> Void)?

        @ObservedObject var state: StateModel
        @State private var isEditingFromList = false
        @State private var showEditorCard = false
        @FocusState private var focusedItemID: UUID?

        init(
            resolver: Resolver,
            state: StateModel,
            showListInitially: Bool = false,
            onAddTreatments: ((Decimal, Decimal, Decimal, String) -> Void)? = nil,
            onDismiss: (() -> Void)? = nil
        ) {
            self.resolver = resolver
            _state = ObservedObject(wrappedValue: state)
            self.showListInitially = showListInitially
            self.onAddTreatments = onAddTreatments
            // Wire optional callback into the state so it can call back when user selects "Add to Treatments"
            self.state.onAddTreatments = onAddTreatments
            self.state.onDismiss = onDismiss
        }

        @Environment(AppState.self) var appState
        @Environment(\.colorScheme) var colorScheme

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
                if state.showListView {
                    listViewContent
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    scannerViewContent
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .gesture(
                DragGesture()
                    .onEnded { value in
                        if value.translation.width > 50 {
                            state.showListView = false
                        } else if value.translation.width < -50 {
                            state.showListView = true
                        }
                    }
            )
            .animation(.easeInOut(duration: 0.3), value: state.showListView)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle(String(localized: state.showListView ? "Scanned Items" : "Barcode Scanner"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if showEditorView {
                        Button(
                            action: {
                                state.cancelEditing()
                            },
                            label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                    Text(String(localized: "Back"))
                                }
                            }
                        )
                        .buttonStyle(BorderlessButtonStyle())
                    } else {
                        Button(
                            action: {
                                state.performDismissal()
                            },
                            label: {
                                Text(String(localized: "Close"))
                            }
                        )
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // Hide the item list button while editing nutrition details
                    if !state.showListView && !showEditorView {
                        Button(
                            action: {
                                state.showListView = true
                            },
                            label: {
                                HStack {
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
                        )
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }
            }
            .sheet(isPresented: $showEditorCard) {
                NavigationStack {
                    NutritionEditorView(
                        state: state,
                        isEditingFromList: $isEditingFromList,
                        onDismissList: { showEditorCard = false }
                    )
                    .navigationTitle(String(localized: "Edit Item"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(String(localized: "Cancel")) {
                                showEditorCard = false
                                if isEditingFromList {
                                    isEditingFromList = false
                                    state.isEditingFromList = false
                                    state.cancelEditing()
                                }
                            }
                        }
                    }
                }
            }
            .onChange(of: showEditorCard) { _, isPresented in
                // If the sheet is dismissed interactively while editing from list, reset editing state
                if !isPresented, isEditingFromList {
                    isEditingFromList = false
                    state.cancelEditing()
                }
            }
            .onAppear {
                configureView()
                state.handleAppear()
                state.showListView = showListInitially
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
                    NutritionEditorView(
                        state: state,
                        isEditingFromList: $isEditingFromList,
                        onDismissList: { state.showListView = true }
                    )

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

                // Custom Keyboard Toolbar (Overlay when keyboard is visible in List)
                if focusedItemID != nil {
                    VStack {
                        Spacer()
                        customKeyboardToolbar
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .zIndex(100)
                    }
                }
            }
            .onChange(of: focusedItemID) { _, newValue in
                if newValue != nil {
                    state.isKeyboardVisible = true
                    state.isScanning = false
                } else {
                    state.isKeyboardVisible = false
                }
            }
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
                        // "Calculator" button removed as per request for live updates
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }

        // MARK: - List View Content

        private var listViewContent: some View {
            ZStack(alignment: .leading) {
                Group {
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
                                    ScannedProductRow(item: item, state: state, focusedItemID: $focusedItemID)
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
                                                state.isEditingFromList = true
                                                showEditorCard = true
                                            } label: {
                                                Label("Edit", systemImage: "pencil")
                                            }
                                            .tint(.blue)
                                        }
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .safeAreaInset(edge: .bottom) {
                            // Show keyboard dismiss button when numpad is visible
                            if focusedItemID != nil {
                                customKeyboardToolbar
                            }
                        }
                        if !state.scannedProducts.isEmpty {
                            // "Use in bolus calculator" button removed for live sync
                        }
                    }
                }

                // Edge Swipe Overlay: Invisible touch zone on the left edge
                // Captures swipes to go back to scanner, preventing conflict with list row swipes
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: 30)
                    .frame(maxHeight: .infinity)
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
                Text("Scan barcodes add items here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    state.showListView = false
                } label: {
                    Label("Start Scanning", systemImage: "barcode.viewfinder")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appState.trioBackgroundColor(for: colorScheme))
        }

        private var customKeyboardToolbar: some View {
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Spacer()
                    Button {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
                    Text("total \(totalCarbs, specifier: "%.1f") g of carbs")
                        .foregroundStyle(.blue)
                }
                .font(.subheadline)
            }
        }

        // MARK: - Helper Functions
    }
}
