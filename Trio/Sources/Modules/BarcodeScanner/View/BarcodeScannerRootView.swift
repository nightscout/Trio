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
        @State private var showAllSearchResults = false

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
            .simultaneousGesture(
                DragGesture()
                    .onEnded { value in
                        if abs(value.translation.width) > abs(value.translation.height) {
                            // Horizontal Swipe - Switch Views
                            // In List View, require Edge Swipe (from left) to avoid conflict with row actions
                            let isEdgeSwipe = value.startLocation.x < 50
                            // Higher threshold to distinguish from accidental diagonal drags
                            let threshold: CGFloat = 80

                            if value.translation.width > threshold {
                                // Swipe Right (Back to Scanner)
                                // Only allow if (Scanner Mode) OR (List Mode AND Edge Swipe)
                                if !state.showListView || isEdgeSwipe {
                                    state.showListView = false
                                }
                            } else if value.translation.width < -threshold {
                                // Swipe Left (Go to List)
                                state.showListView = true
                            }
                        }
                    }
            )
            .animation(.easeInOut(duration: 0.3), value: state.showListView)
            .background(appState.trioBackgroundColor(for: colorScheme).ignoresSafeArea())
            .navigationTitle(String(localized: state.showListView ? "Scanned Items" : "Barcode Scanner"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(content: {
                ToolbarItem(placement: .topBarLeading) {
                    if state.showEditorView {
                        Button(
                            action: {
                                state.cancelEditing()
                            },
                            label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                    Text(String(localized: "Back"))
                                        .fixedSize(horizontal: true, vertical: false)
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
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        )
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // Hide the item list button while editing nutrition details
                    if state.showListView {
                        Button(
                            action: {
                                state.showListView = false
                            },
                            label: {
                                Image(systemName: "barcode.viewfinder")
                                    .font(.body)
                            }
                        )
                    } else if !state.showEditorView {
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
                        .padding(.bottom, 120)

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

        // MARK: - Camera Action Buttons

        private var cameraActionButtons: some View {
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
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(state.isScanning ? .orange : .insulin)

                if !state.scannedProducts.isEmpty {
                    // "Calculator" button removed as per request for live updates
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }

        // MARK: - List View Content

        private var listViewContent: some View {
            ZStack(alignment: .leading) {
                List {
                    // Search Section
                    Section {
                        BarcodeScanner.ProductSearchField(
                            searchText: $state.searchQuery,
                            isFocused: $isSearchFocused,
                            onSubmit: {
                                showAllSearchResults = false
                                state.performFoodSearch()
                            },
                            onClear: {
                                state.searchQuery = ""
                                state.searchResults = []
                                showAllSearchResults = false
                            },
                            onChange: {
                                showAllSearchResults = false
                            }
                        )
                        .padding(.horizontal)
                        .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                        if state.isSearching {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .padding(.vertical, 8)
                                Spacer()
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        } else if let error = state.searchError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        } else if !state.searchResults.isEmpty {
                            let displayResults =
                                showAllSearchResults ? state.searchResults : Array(state.searchResults.prefix(5))
                            ForEach(displayResults) { item in
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
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            }

                            if state.searchResults.count > 5 {
                                Button {
                                    withAnimation {
                                        showAllSearchResults.toggle()
                                    }
                                } label: {
                                    HStack {
                                        Text(
                                            showAllSearchResults
                                                ? "Show less" : "Show \(state.searchResults.count - 5) more results"
                                        )
                                        .font(.caption.weight(.medium))
                                        Image(systemName: showAllSearchResults ? "chevron.up" : "chevron.down")
                                            .font(.caption)
                                    }
                                    .foregroundStyle(.blue)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                    }

                    if state.scannedProducts.isEmpty, state.searchResults.isEmpty, !state.isSearching {
                        emptyListView
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                    }

                    if !state.scannedProducts.isEmpty {
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
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)

                // Edge Swipe Overlay: Invisible touch zone on the left edge
                // Captures swipes to go back to scanner, preventing conflict with list row swipes
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: 30)
                    .frame(maxHeight: .infinity)
            }
        }

        private var emptyListView: some View {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                Text(String(localized: "No items scanned yet"))
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
                Text(
                    "\(state.scannedProducts.count) Item\(state.scannedProducts.count == 1 ? "" : "s") Scanned"
                )
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
