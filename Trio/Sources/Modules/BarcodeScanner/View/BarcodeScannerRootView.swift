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
        @FocusState private var isSearchFocused: Bool

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
            .animation(.easeInOut(duration: 0.3), value: state.showListView)
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
                                            .padding(.bottom, 100)
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
            ZStack {
                switch state.cameraStatus {
                case .authorized:
                    ZStack {
                        ScannerPreviewView(
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
                                .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                        )
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        }

        // MARK: - List View Content

        private var listViewContent: some View {
            List {
                Section {
                    // Search Bar
                    BarcodeScanner.ProductSearchField(
                        searchText: $state.searchQuery,
                        isFocused: $isSearchFocused,
                        onSubmit: {
                            state.performFoodSearch()
                        },
                        onClear: {
                            state.searchQuery = ""
                            state.searchResults = []
                        },
                        onChange: {
                            state.searchResults = []
                            state.searchError = nil
                            state.hasMoreSearchResults = false
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 10, trailing: 0))

                    // Search Results progress spinner and error display
                    if state.isSearching {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding(.vertical, 8)
                            Spacer()
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else if let error = state.searchError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    } else if !state.searchResults.isEmpty {
                        ForEach(state.searchResults) { item in
                            BarcodeScanner.FoodSearchResultRow(item: item) {
                                withAnimation {
                                    var mutableItem = item
                                    mutableItem.amount = item.servingQuantity ?? 100
                                    state.scannedProducts.append(mutableItem)
                                    state.searchQuery = ""
                                    state.searchResults = []
                                    isSearchFocused = false
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        }

                        // Show "Show more results" button if there are more results
                        if state.hasMoreSearchResults {
                            Button {
                                state.loadMoreSearchResults()
                            } label: {
                                HStack {
                                    if state.isLoadingMoreSearchResults {
                                        ProgressView()
                                            .scaleEffect(0.9)
                                    } else {
                                        Text("Show 4 more results")
                                            .font(.caption.weight(.medium))
                                        Image(systemName: "chevron.down")
                                            .font(.caption)
                                    }
                                }
                                .foregroundStyle(.blue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            .disabled(state.isLoadingMoreSearchResults)
                        }
                    }

                    // Info about how much you scanned and total carbs
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

                // Scanned products
                // Seperate Section for better grouping and styling
                if !state.scannedProducts.isEmpty {
                    Section {
                        ForEach(state.scannedProducts) { item in
                            ScannedProductRow(item: item, state: state, focusedItemID: $focusedItemID)
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
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
            .listSectionSpacing(8)
            .contentMargins(.top, 4)
        }

        private func actionButtonsForScannedProduct(for product: BarcodeScanner.FoodItem) -> some View {
            Group {
                Button(role: .destructive) {
                    withAnimation {
                        state.removeScannedProduct(product)
                    }
                } label: {
                    Label("Delete", systemImage: "trash.fill")
                }
                .tint(.red)

                Button {
                    state.editScannedProduct(product)
                    isEditingFromList = true
                    state.isEditingFromList = true
                    showEditorCard = true
                } label: {
                    Label("Edit", systemImage: "pencil")
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
