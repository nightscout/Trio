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
            .navigationTitle(String(localized: showListView ? "Scanned Items" : "Barcode Scanner"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if showListView {
                        Button(
                            action: {
                                showListView = false
                            },
                            label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                    Text("Scanner")
                                }
                            }
                        )
                        .buttonStyle(BorderlessButtonStyle())
                    } else {
                        Button(
                            action: {
                                state.hideModal()
                            },
                            label: {
                                HStack(spacing: 4) {
                                    Text(String(localized: "Close"))
                                }
                            }
                        )
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !showListView {
                        Button(
                            action: {
                                showListView = true
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
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button(
                            action: {
                                dismissKeyboard()
                            },
                            label: {
                                HStack {
                                    Image(systemName: "keyboard.chevron.compact.down")
                                    Text(String(localized: "Done"))
                                }
                            }
                        )
                        .buttonStyle(BorderlessButtonStyle())
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
                    NutritionEditorView(
                        state: state,
                        focusedField: $focusedField,
                        isEditingFromList: $isEditingFromList,
                        onDismissList: { showListView = true }
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

        // MARK: - List View Content

        private var listViewContent: some View {
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
                Text("Scan barcodes add items here.")
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appState.trioBackgroundColor(for: colorScheme))
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
    }
}
