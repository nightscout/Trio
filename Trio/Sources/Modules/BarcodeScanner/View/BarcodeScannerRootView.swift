import CodeScanner
import SwiftUI
import Swinject

private func localizedScanFailureMessage(for error: ScanError) -> String {
    switch error {
    case .badInput:
        return String(localized: "The camera could not be accessed.")
    case .badOutput:
        return String(localized: "This device can't read barcodes with the camera.")
    case .permissionDenied:
        return String(
            localized: "Camera permissions were denied. Enable them in Settings to continue."
        )
    case let .initError(underlying):
        return (underlying as? LocalizedError)?.errorDescription ?? underlying.localizedDescription
    }
}

// MARK: - Root View

extension BarcodeScanner {
    struct RootView: BaseView {
        let resolver: Resolver
        var showListInitially: Bool = false

        @ObservedObject var state: StateModel
        @State private var isEditingFromList = false
        @State private var showEditorCard = false

        @FocusState private var focusedItemID: UUID?
        @FocusState private var isSearchFocused: Bool

        init(
            resolver: Resolver,
            state: StateModel,
            showListInitially: Bool = false,
            onDismiss: (() -> Void)? = nil
        ) {
            self.resolver = resolver
            _state = ObservedObject(wrappedValue: state)
            self.showListInitially = showListInitially
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

        private var torchToggleButton: some View {
            Button {
                state.isTorchOn.toggle()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: state.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                        .font(.title2)
                    Text(String(localized: "Flash"))
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .safeAreaPadding(.bottom, 8)
            .accessibilityLabel(String(localized: "Flash"))
        }

        var body: some View {
            VStack {
                if !state.showEditorView {
                    Picker("", selection: Binding(
                        get: { state.showListView },
                        set: { state.showListView = $0 }
                    )) {
                        Text(String(localized: "Scanner")).tag(false)
                        Text(String(localized: "Meal")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                }

                ZStack {
                    if state.showListView {
                        listViewContent
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    } else {
                        scannerViewContent
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
            }
            .background(appState.trioBackgroundColor(for: colorScheme).ignoresSafeArea())
            .navigationTitle(String(localized: "Barcode Scanner"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(content: {
                ToolbarItem(placement: .topBarLeading) {
                    Button(
                        action: {
                            state.performDismissal()
                        },
                        label: {
                            Text("Close")
                        }
                    )
                }
            })
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
                                // Robust cleanup: Check either local or state flag
                                if isEditingFromList || state.isEditingFromList {
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
                if !isPresented {
                    if isEditingFromList || state.isEditingFromList {
                        isEditingFromList = false
                        state.isEditingFromList = false
                        state.cancelEditing()
                    }
                }
            }
            .onAppear {
                configureView()
                state.handleAppear()
                state.showListView = showListInitially
            }
            .onDisappear {
                state.isTorchOn = false
            }
            .onChange(of: state.showListView) { _, isMeal in
                if isMeal { state.isTorchOn = false }
            }
            .onChange(of: state.showEditorView) { _, showsEditor in
                if showsEditor { state.isTorchOn = false }
            }
            .onChange(of: state.isFetchingProduct) { _, fetching in
                if fetching { state.isTorchOn = false }
            }
        }

        // MARK: - Scanner View Content

        private var scannerViewContent: some View {
            Group {
                if state.showEditorView {
                    // Show full editor view when product/nutrition data is available
                    NutritionEditorView(
                        state: state,
                        isEditingFromList: $isEditingFromList,
                        onDismissList: { state.showListView = true }
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    GeometryReader { geo in
                        ScrollView {
                            ZStack {
                                if state.isFetchingProduct {
                                    // Loading state
                                    loadingView
                                        .transition(.opacity)
                                } else {
                                    // Scanner view
                                    fullScreenCameraView
                                        .transition(.move(edge: .leading).combined(with: .opacity))
                                }

                                // Error overlay (always visible if there's an error)
                                if let message = state.errorMessage {
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
                                    }
                                    .allowsHitTesting(false)
                                }
                            }
                            .frame(minHeight: geo.size.height)
                        }
                        .scrollIndicators(.hidden)
                    }
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
                    String(localized: "Looking up product…")
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        // MARK: - Full Screen Camera View

        private var fullScreenCameraView: some View {
            VStack {
                ZStack {
                    switch state.cameraStatus {
                    case .authorized:
                        CodeScannerView(
                            codeTypes: [.ean13, .ean8, .upce, .code128, .code39],
                            scanMode: .continuous,
                            requiresPhotoOutput: false,
                            isTorchOn: state.isTorchOn,
                            isPaused: !state.isScanning,
                            completion: { result in
                                switch result {
                                case let .success(scan):
                                    state.didDetect(barcode: scan.string)
                                case let .failure(error):
                                    state.reportScannerIssue(localizedScanFailureMessage(for: error))
                                }
                            }
                        )

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
                            Label(
                                String(localized: "Enable camera access to start scanning."),
                                systemImage: "lock.shield"
                            )
                            .font(.subheadline)
                            Button(String(localized: "Open Settings"), action: state.openAppSettings)
                                .buttonStyle(.borderedProminent)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.9))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                )
                .padding(.horizontal)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if state.cameraStatus == .authorized {
                    torchToggleButton
                }
            }
        }

        // MARK: - List View Content

        private var listViewContent: some View {
            List {
                Section {
                    // Food Search Widget
                    BarcodeScanner.FoodSearchWidget(
                        searchText: $state.searchQuery,
                        isFocused: $isSearchFocused,
                        isSearching: state.isSearching,
                        searchError: state.searchError,
                        searchResults: state.searchResults,
                        hasMoreSearchResults: state.hasMoreSearchResults,
                        isLoadingMoreSearchResults: state.isLoadingMoreSearchResults,
                        onSubmit: { state.performFoodSearch() },
                        onClear: {
                            state.searchQuery = ""
                            state.searchResults = []
                        },
                        onChange: {
                            state.searchResults = []
                            state.searchError = nil
                            state.hasMoreSearchResults = false
                        },
                        onItemAdd: { item in
                            var mutableItem = item
                            mutableItem.amount = item.servingQuantity ?? 100
                            state.scannedProducts.append(mutableItem)
                            state.searchQuery = ""
                            state.searchResults = []
                            isSearchFocused = false
                        },
                        onLoadMore: { state.loadMoreSearchResults() }
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 10, trailing: 0))
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                BarcodeScanner.ScannedProductsListBody(
                    state: state,
                    focusedItemID: $focusedItemID,
                    onEdit: { product in
                        state.editScannedProduct(product)
                        isEditingFromList = true
                        state.isEditingFromList = true
                        showEditorCard = true
                    }
                )
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
            .listSectionSpacing(8)
            .contentMargins(.top, 4)
        }
    }
}
