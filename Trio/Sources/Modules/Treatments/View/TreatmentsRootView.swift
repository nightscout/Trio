import Charts
import CoreData
import LoopKitUI
import SwiftUI
import Swinject

extension Treatments {
    struct RootView: BaseView {
        enum FocusedField {
            case carbs
            case fat
            case protein
            case bolus
        }

        @FocusState private var focusedField: FocusedField?

        let resolver: Resolver
        var openWithScanner: Bool = false

        @State var state = StateModel()

        @State private var showPresetSheet = false
        @State private var autofocus: Bool = true
        @State private var calculatorDetent = PresentationDetent.large
        @State private var pushed: Bool = false
        @State private var debounce: DispatchWorkItem?

        // Food search state
        @State private var searchQuery = ""
        @State private var searchResults: [BarcodeScanner.FoodItem] = []
        @State private var isSearching = false
        @State private var searchError: String?
        @State private var searchDebounce: DispatchWorkItem?
        @State private var showAllSearchResults = false
        @FocusState private var isSearchFocused: Bool

        private enum Config {
            static let dividerHeight: CGFloat = 2
            static let spacing: CGFloat = 3
        }

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumIntegerDigits = 2
            formatter.maximumFractionDigits = 3
            return formatter
        }

        private var mealFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumIntegerDigits = 3
            formatter.maximumFractionDigits = 0
            return formatter
        }

        private var gluoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            if state.units == .mmolL {
                formatter.maximumIntegerDigits = 2
                formatter.maximumFractionDigits = 1
            } else {
                formatter.maximumIntegerDigits = 3
                formatter.maximumFractionDigits = 0
            }
            return formatter
        }

        private var fractionDigits: Int {
            if state.units == .mmolL {
                return 1
            } else { return 0 }
        }

        /// Handles macro input (carb, fat, protein) in a debounced fashion.
        func handleDebouncedInput() {
            debounce?.cancel()
            debounce = DispatchWorkItem { [self] in
                Task {
                    await state.updateForecasts()
                    state.insulinCalculated = await state.calculateInsulin()
                }
            }
            if let debounce = debounce {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: debounce)
            }
        }

        @ViewBuilder private func proteinAndFat() -> some View {
            HStack {
                VStack {
                    HStack {
                        Text("Protein")
                        TextFieldWithToolBar(
                            text: $state.protein,
                            placeholder: "0",
                            keyboardType: .numberPad,
                            numberFormatter: mealFormatter,
                            showArrows: true,
                            previousTextField: { focusedField = previousField(from: .protein) },
                            nextTextField: { focusedField = nextField(from: .protein) },
                            unitsText: String(localized: "g", comment: "Units for carbs")
                        )
                        .focused($focusedField, equals: .protein)
                        .onChange(of: state.protein) {
                            handleDebouncedInput()
                        }
                    }
                    if state.scannedProtein > 0 && !state.settings.settings.barcodeScannerOnlyCarbs {
                        Text("+ \(Double(truncating: state.scannedProtein as NSNumber), specifier: "%.1f")g")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }

                Divider().foregroundStyle(.primary).fontWeight(.bold).frame(width: 10)

                VStack {
                    HStack {
                        Text("Fat")
                        TextFieldWithToolBar(
                            text: $state.fat,
                            placeholder: "0",
                            keyboardType: .numberPad,
                            numberFormatter: mealFormatter,
                            showArrows: true,
                            previousTextField: { focusedField = previousField(from: .fat) },
                            nextTextField: { focusedField = nextField(from: .fat) },
                            unitsText: String(localized: "g", comment: "Units for carbs")
                        )
                        .focused($focusedField, equals: .fat)
                        .onChange(of: state.fat) {
                            handleDebouncedInput()
                        }
                    }
                    if state.scannedFat > 0 && !state.settings.settings.barcodeScannerOnlyCarbs {
                        Text("+ \(Double(truncating: state.scannedFat as NSNumber), specifier: "%.1f")g")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
            }
        }

        @ViewBuilder var foodSearch: some View {
            // Food Search & Quick Actions
            if state.settings != nil && state.settings.settings.barcodeScannerEnabled {
                // Combined search bar with action buttons
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        // Scanner button
                        Button {
                            configureAndShowScanner(showList: false)
                        } label: {
                            Image(systemName: "barcode.viewfinder")
                                .font(.title2)
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)

                        // Search field
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("Search foods...", text: $searchQuery)
                                .focused($isSearchFocused)
                                .textFieldStyle(.plain)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .submitLabel(.search)
                                .onSubmit {
                                    showAllSearchResults = false
                                    performFoodSearch()
                                }
                                .toolbar {
                                    if isSearchFocused {
                                        ToolbarItemGroup(placement: .keyboard) {
                                            Button(action: {
                                                searchQuery = ""
                                            }) {
                                                Image(systemName: "trash")
                                            }
                                            Spacer()
                                            Button(action: {
                                                isSearchFocused = false
                                            }) {
                                                Image(systemName: "keyboard.chevron.compact.down")
                                            }
                                        }
                                    }
                                }
                                .onChange(of: searchQuery) { _, _ in
                                    showAllSearchResults = false
                                }
                            if !searchQuery.isEmpty {
                                Button {
                                    searchQuery = ""
                                    searchResults = []
                                    showAllSearchResults = false
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        // List button
                        Button {
                            configureAndShowScanner(showList: true)
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "list.bullet")
                                    .font(.title2)
                                    .foregroundStyle(.blue)

                                if !scannerState.scannedProducts.isEmpty {
                                    Text("\(scannerState.scannedProducts.count)")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white)
                                        .padding(4)
                                        .background(Circle().fill(Color.red))
                                        .offset(x: 8, y: -8)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    // Search results and Spinner
                    if isSearching {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding(.vertical, 8)
                            Spacer()
                        }
                    } else if let error = searchError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if !searchResults.isEmpty {
                        VStack(spacing: 0) {
                            let displayResults = showAllSearchResults ? searchResults : Array(searchResults.prefix(5))
                            ForEach(displayResults) { item in
                                FoodSearchResultRow(item: item) {
                                    addSearchResultToMeal(item)
                                }
                                if item.id != displayResults.last?.id {
                                    Divider().opacity(0.3)
                                }
                            }

                            if searchResults.count > 5 {
                                Button {
                                    withAnimation {
                                        showAllSearchResults.toggle()
                                    }
                                } label: {
                                    HStack {
                                        Text(
                                            showAllSearchResults ? "Show less" :
                                                "Show \(searchResults.count - 5) more results"
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
                            }
                        }
                    }
                }
            }
        }

        @ViewBuilder private func carbsTextField() -> some View {
            HStack {
                Text("Carbs")
                Spacer()
                TextFieldWithToolBar(
                    text: $state.carbs,
                    placeholder: "0",
                    keyboardType: .numberPad,
                    numberFormatter: mealFormatter,
                    showArrows: true,
                    previousTextField: { focusedField = previousField(from: .carbs) },
                    nextTextField: { focusedField = nextField(from: .carbs) },
                    unitsText: String(localized: "g", comment: "Units for carbs")
                )
                .focused($focusedField, equals: .carbs)
                .onChange(of: state.carbs) {
                    handleDebouncedInput()
                }
                if state.scannedCarbs > 0 {
                    Text("+ \(Double(truncating: state.scannedCarbs as NSNumber), specifier: "%.1f")g")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
        }

        /// Determines the next field to focus on based on the current focused field.
        ///
        /// This function handles the tab order navigation between input fields,
        /// taking into account whether fat/protein fields are visible based on user settings.
        ///
        /// - Parameter current: The currently focused field
        /// - Returns: The next field that should receive focus, or nil if there is no next field
        private func nextField(from current: FocusedField) -> FocusedField? {
            // If fat/protein fields are hidden, skip them in navigation
            let showFPU = state.useFPUconversion

            switch current {
            case .fat:
                return .bolus
            case .protein:
                return .fat
            case .carbs:
                return showFPU ? .protein : .bolus
            case .bolus:
                return .carbs
            }
        }

        /// Determines the previous field to focus on based on the current focused field.
        ///
        /// This function handles the reverse tab order navigation between input fields,
        /// taking into account whether fat/protein fields are visible based on user settings.
        ///
        /// - Parameter current: The currently focused field
        /// - Returns: The previous field that should receive focus, or nil if there is no previous field
        private func previousField(from current: FocusedField) -> FocusedField? {
            let showFPU = state.useFPUconversion

            switch current {
            case .fat:
                return .protein
            case .protein:
                return .carbs
            case .carbs:
                return .bolus
            case .bolus:
                return showFPU ? .fat : .carbs
            }
        }

        @ViewBuilder var inputsView: some View {
            VStack {
                Spacer()
                carbsTextField()

                Divider()

                if state.useFPUconversion {
                    proteinAndFat()
                    Divider()
                }

                // Time
                HStack {
                    Image(systemName: "clock")

                    Spacer()
                    if !pushed {
                        Button {
                            pushed = true
                        } label: { Text("Now") }.buttonStyle(.borderless).foregroundColor(.secondary)
                            .padding(.trailing, 5)
                    } else {
                        Button { state.date = state.date.addingTimeInterval(-15.minutes.timeInterval) }
                        label: { Image(systemName: "minus.circle") }.tint(.blue).buttonStyle(.borderless)

                        DatePicker(
                            "Time",
                            selection: $state.date,
                            displayedComponents: [.hourAndMinute]
                        ).controlSize(.mini)
                            .labelsHidden()
                            .onChange(of: state.date) { _, _ in
                                // Trigger simulation when date changes to update forecasts for backdated carbs
                                Task {
                                    // `updateForecasts()` does update the `simulatedDetermination` of type `Determination?` var on the main thread, so I can use this to pass its cob value into the bolus calc manager
                                    await state.updateForecasts()
                                    state.insulinCalculated = await state.calculateInsulin()
                                }
                            }
                        Button {
                            state.date = state.date.addingTimeInterval(15.minutes.timeInterval)
                        }
                        label: { Image(systemName: "plus.circle") }.tint(.blue).buttonStyle(.borderless)
                    }
                }

                Divider()

                // Notes
                HStack {
                    Image(systemName: "square.and.pencil")
                    TextFieldWithToolBarString(
                        text: $state.note,
                        placeholder: String(localized: "Note..."),
                        maxLength: 25
                    )
                }
                Spacer()
            }
        }

        @ViewBuilder var optionsView: some View {
            VStack {
                if state.fattyMeals || state.sweetMeals {
                    Spacer()
                    HStack(spacing: 10) {
                        if state.fattyMeals {
                            Toggle(isOn: $state.useFattyMealCorrectionFactor) {
                                Text("Reduced Bolus")
                            }
                            .toggleStyle(RadioButtonToggleStyle())
                            .font(.footnote)
                            .onChange(of: state.useFattyMealCorrectionFactor) {
                                Task {
                                    state.insulinCalculated = await state.calculateInsulin()
                                    if state.useFattyMealCorrectionFactor {
                                        state.useSuperBolus = false
                                    }
                                }
                            }
                        }
                        if state.sweetMeals {
                            Toggle(isOn: $state.useSuperBolus) {
                                Text("Super Bolus")
                            }
                            .toggleStyle(RadioButtonToggleStyle())
                            .font(.footnote)
                            .onChange(of: state.useSuperBolus) {
                                Task {
                                    state.insulinCalculated = await state.calculateInsulin()
                                    if state.useSuperBolus {
                                        state.useFattyMealCorrectionFactor = false
                                    }
                                }
                            }
                        }
                    }
                    Divider()
                }

                Spacer()

                HStack {
                    HStack {
                        Text("Recommendation")
                        Button(action: {
                            state.showInfo.toggle()
                        }, label: {
                            Image(systemName: "info.circle")
                        })
                            .foregroundStyle(.blue)
                            .buttonStyle(PlainButtonStyle())
                    }
                    Spacer()
                    Button {
                        state.amount = state.insulinCalculated
                    } label: {
                        HStack {
                            Text(
                                formatter
                                    .string(from: Double(state.insulinCalculated) as NSNumber) ?? ""
                            )

                            Text(
                                String(
                                    localized:
                                    " U",
                                    comment: "Unit in number of units delivered (keep the space character!)"
                                )
                            ).foregroundColor(.secondary)
                        }
                    }
                    .disabled(state.insulinCalculated == 0 || state.amount == state.insulinCalculated)
                    .buttonStyle(.bordered).padding(.trailing, -10)
                }

                Divider()
                Spacer()

                HStack {
                    Text("Bolus")
                    Spacer()
                    TextFieldWithToolBar(
                        text: $state.amount,
                        placeholder: "0",
                        textColor: colorScheme == .dark ? .white : .blue,
                        maxLength: 5,
                        numberFormatter: formatter,
                        showArrows: true,
                        previousTextField: { focusedField = previousField(from: .bolus) },
                        nextTextField: { focusedField = nextField(from: .bolus) },
                        unitsText: String(localized: "U", comment: "Units for bolus amount")
                    ).focused($focusedField, equals: .bolus)
                        .onChange(of: state.amount) {
                            Task {
                                await state.updateForecasts()
                            }
                        }
                }

                Divider()
                Spacer()

                HStack {
                    Text("External Insulin")
                    Spacer()
                    Toggle("", isOn: $state.externalInsulin).toggleStyle(CheckboxToggleStyle())
                }

                Spacer()
            }
        }

        func treatmentButtonCompact() -> some View {
            var treatmentButtonBackground = Color(.systemBlue)
            if limitExceeded {
                treatmentButtonBackground = Color(.systemRed)
            } else if disableTaskButton {
                treatmentButtonBackground = Color(.systemGray)
            }

            return Button {
                if bolusWarning.shouldConfirm {
                    showConfirmDialogForBolusing = true
                } else {
                    state.invokeTreatmentsTask()
                }
            } label: {
                HStack {
                    if state.isBolusInProgress && state.amount > 0 &&
                        !state.externalInsulin && (state.carbs == 0 || state.fat == 0 || state.protein == 0)
                    {
                        ProgressView()
                    }
                    taskButtonLabel
                }
                .font(.headline)
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: 50)
                .background(treatmentButtonBackground)
                .clipShape(RoundedRectangle(cornerRadius: 15))
            }
            .disabled(disableTaskButton)
            .shadow(radius: 3)
            .padding(.horizontal)
            .confirmationDialog(
                bolusWarning.warningMessage + " Bolus \(state.amount.description) U?",
                isPresented: $showConfirmDialogForBolusing,
                titleVisibility: .visible
            ) {
                Button("Cancel", role: .cancel) {}
                Button(
                    bolusWarning.warningMessage.isEmpty ? "Enact Bolus" : "Ignore Warning and Enact Bolus",
                    role: bolusWarning.warningMessage.isEmpty ? nil : .destructive
                ) {
                    state.invokeTreatmentsTask()
                }
            }
        }

        @ViewBuilder func listView() -> some View {
            List {
                Section {
                    foodSearch
                }.listRowBackground(Color.chart)

                Section {
                    ForecastChart(state: state)
                        .padding(.vertical)
                }.listRowBackground(Color.chart)

                Section {
                    inputsView
                }.listRowBackground(Color.chart)

                Section {
                    optionsView
                }.listRowBackground(Color.chart)

                treatmentButton
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(sectionSpacing)
            .contentMargins(.top, 0, for: .scrollContent)
        }

        var body: some View {
            ZStack(alignment: .center) {
                listView()

                if state.isAwaitingDeterminationResult {
                    CustomProgressView(text: progressText.displayName)
                }
            }
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .blur(radius: state.showInfo || state.isAwaitingDeterminationResult ? 3 : 0)
            .navigationTitle("Treatments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(content: {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        state.hideModal()
                    } label: {
                        Text("Close")
                    }
                }
                if state.displayPresets {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: {
                            showPresetSheet = true
                        }, label: {
                            HStack {
                                Text("Presets")
                                Image(systemName: "plus")
                            }
                        })
                    }
                }
            })
            .onAppear {
                configureView {
                    state.isActive = true
                    Task { @MainActor in
                        state.insulinCalculated = await state.calculateInsulin()
                    }
                    // Auto-open scanner if requested
                    if openWithScanner {
                        configureAndShowScanner(showList: false)
                    }
                }
            }
            .onDisappear {
                state.isActive = false
                state.addButtonPressed = false

                // Cancel all Combine subscriptions and unregister State from broadcaster
                state.cleanupTreatmentState()
            }
            .sheet(isPresented: $state.showInfo) {
                PopupView(state: state)
            }
            .sheet(isPresented: $showPresetSheet, onDismiss: {
                showPresetSheet = false
            }) {
                MealPresetView(state: state)
            }
            .alert("Error while processing Treatment", isPresented: $state.showDeterminationFailureAlert) {
                Button("OK", role: .cancel) {
                    state.hideModal()
                }
            } message: {
                Text("\(state.determinationFailureMessage)")
            }
            .sheet(isPresented: $showBarcodeScanner) {
                NavigationStack {
                    BarcodeScanner.RootView(
                        resolver: resolver,
                        state: scannerState,
                        showListInitially: initialShowList,
                        onAddTreatments: { carbs, fat, protein, note in
                            // Directly merge scanned amounts into Treatments state
                            Task { @MainActor in
                                state.addScannedAmounts(carbs: carbs, fat: fat, protein: protein, note: note)
                                // Force forecasts update and recalc insulin
                                await state.updateForecasts(force: true)
                                state.insulinCalculated = await state.calculateInsulin()
                            }
                        },
                        onDismiss: { showBarcodeScanner = false }
                    )
                    .environment(appState)
                }
                .onChange(of: scannerState.scannedProducts) {
                    syncScannedAmounts()
                }
            }
        }

        @StateObject private var scannerState = BarcodeScanner.StateModel()
        @State private var showBarcodeScanner = false
        @State private var initialShowList = false

        func configureAndShowScanner(showList: Bool) {
            scannerState.showListView = showList
            showBarcodeScanner = true
            initialShowList = showList
        }

        /// Performs food search using Open Food Facts API
        private func performFoodSearch() {
            searchError = nil

            let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else {
                searchResults = []
                isSearching = false
                return
            }

            // Show spinner immediately
            isSearching = true
            searchResults = [] // Clear old results so spinner shows

            Task { @MainActor in
                do {
                    let client = BarcodeScanner.OpenFoodFactsClient()
                    self.searchResults = try await client.searchProducts(query: query)
                } catch {
                    self.searchError = error.localizedDescription
                    self.searchResults = []
                }
                self.isSearching = false
            }
        }

        /// Adds a search result to the scanned products and updates calculations
        private func addSearchResultToMeal(_ item: BarcodeScanner.FoodItem) {
            // Add to scanner state's scanned products with default amount
            var mutableItem = item
            mutableItem.amount = item.servingQuantity ?? 100 // Default to serving or 100g
            scannerState.scannedProducts.append(mutableItem)

            // Clear search
            searchQuery = ""
            searchResults = []

            // Sync amounts and recalculate
            syncScannedAmounts()
            isSearchFocused = false
        }

        private func syncScannedAmounts() {
            let totalCarbs = scannerState.scannedProducts.reduce(into: 0.0) { result, item in
                let carbsPer100 = item.nutriments.carbohydratesPer100g ?? 0
                let amount = item.amount.isFinite ? item.amount : 0
                result += (carbsPer100 * amount) / 100.0
            }
            let totalProtein = scannerState.scannedProducts.reduce(into: 0.0) { result, item in
                let protPer100 = item.nutriments.proteinPer100g ?? 0
                let amount = item.amount.isFinite ? item.amount : 0
                result += (protPer100 * amount) / 100.0
            }
            let totalFat = scannerState.scannedProducts.reduce(into: 0.0) { result, item in
                let fatPer100 = item.nutriments.fatPer100g ?? 0
                let amount = item.amount.isFinite ? item.amount : 0
                result += (fatPer100 * amount) / 100.0
            }

            state.scannedCarbs = Decimal(totalCarbs)
            state.scannedProtein = Decimal(totalProtein)
            state.scannedFat = Decimal(totalFat)

            // Trigger a recalculation immediately (sheet may make view inactive, so do it directly)
            Task { @MainActor in
                // Update forecasts and insulin immediately (force update even if view not active)
                debug(
                    .bolusState,
                    "syncScannedAmounts: carbs=\(state.carbs) scannedCarbs=\(state.scannedCarbs) totalCarbs=\(state.carbs + state.scannedCarbs)"
                )
                await state.updateForecasts(force: true)
                state.insulinCalculated = await state.calculateInsulin()
                debug(.bolusState, "syncScannedAmounts: insulinCalculated=\(state.insulinCalculated)")
            }

            // Also keep the debounced update for smoother UI updates
            handleDebouncedInput()
        }

        var progressText: ProgressText {
            switch (state.amount > 0, state.carbs > 0) {
            case (true, true):
                return .updatingIOBandCOB
            case (false, true):
                return .updatingCOB
            case (true, false):
                return .updatingIOB
            default:
                return .updatingTreatments
            }
        }

        @State private var showConfirmDialogForBolusing = false

        private var bolusWarning: (shouldConfirm: Bool, warningMessage: String, color: Color) {
            let isGlucoseVeryLow = state.currentBG < 54
            let isForecastVeryLow = state.minPredBG < 54

            // Only warn when enacting a bolus via pump
            guard !state.externalInsulin, state.amount > 0 else {
                return (false, "", .primary)
            }

            let warningMessage = isGlucoseVeryLow ? String(localized: "Glucose is very low.") :
                isForecastVeryLow ? String(localized: "Glucose forecast is very low.") :
                ""

            let warningColor: Color = isGlucoseVeryLow ? .red : colorScheme == .dark ? .orange : .accentColor

            let shouldConfirm = state.confirmBolus && (isGlucoseVeryLow || isForecastVeryLow)

            return (shouldConfirm, warningMessage, warningColor)
        }

        var treatmentButton: some View {
            var treatmentButtonBackground = Color(.systemBlue)
            if limitExceeded {
                treatmentButtonBackground = Color(.systemRed)
            } else if disableTaskButton {
                treatmentButtonBackground = Color(.systemGray)
            }

            return Section {
                Button {
                    if bolusWarning.shouldConfirm {
                        showConfirmDialogForBolusing = true
                    } else {
                        state.invokeTreatmentsTask()
                    }
                } label: {
                    HStack {
                        if state.isBolusInProgress && state.amount > 0 &&
                            !state
                            .externalInsulin &&
                            (
                                state.carbs == 0 && state.scannedCarbs == 0 || state.fat == 0 && state.scannedFat == 0 || state
                                    .protein == 0 && state.scannedProtein == 0
                            )
                        {
                            ProgressView()
                        }
                        taskButtonLabel
                    }
                    .font(.headline)
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 35)
                }
                .disabled(disableTaskButton)
                .listRowBackground(treatmentButtonBackground)
                .shadow(radius: 3)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .confirmationDialog(
                    bolusWarning.warningMessage + " Bolus \(state.amount.description) U?",
                    isPresented: $showConfirmDialogForBolusing,
                    titleVisibility: .visible
                ) {
                    Button("Cancel", role: .cancel) {}
                    Button(
                        bolusWarning.warningMessage.isEmpty ? "Enact Bolus" : "Ignore Warning and Enact Bolus",
                        role: bolusWarning.warningMessage.isEmpty ? nil : .destructive
                    ) {
                        state.invokeTreatmentsTask()
                    }
                }
            } header: {
                if !bolusWarning.warningMessage.isEmpty {
                    Text(bolusWarning.warningMessage)
                        .textCase(nil)
                        .font(.subheadline)
                        .foregroundColor(bolusWarning.color)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, -22)
                }
            }
        }

        private var taskButtonLabel: some View {
            if pumpBolusLimitExceeded {
                return Text("Max Bolus of \(state.maxBolus.description) U Exceeded")
            } else if externalBolusLimitExceeded {
                return Text("Max External Bolus of \(state.maxExternal.description) U Exceeded")
            } else if carbLimitExceeded {
                return Text("Max Carbs of \(state.maxCarbs.description) g Exceeded")
            } else if fatLimitExceeded {
                return Text("Max Fat of \(state.maxFat.description) g Exceeded")
            } else if proteinLimitExceeded {
                return Text("Max Protein of \(state.maxProtein.description) g Exceeded")
            }

            let hasInsulin = state.amount > 0
            let hasCarbs = state.carbs > 0 || state.scannedCarbs > 0
            let hasFatOrProtein = state.fat > 0 || state.scannedFat > 0 || state.protein > 0 || state.scannedProtein > 0
            let bolusString = state.externalInsulin ? String(localized: "External Insulin") : String(localized: "Enact Bolus")

            if state.isBolusInProgress && hasInsulin && !state.externalInsulin && (!hasCarbs || !hasFatOrProtein) {
                return Text("Bolus In Progress...")
            }

            switch (hasInsulin, hasCarbs, hasFatOrProtein) {
            case (true, true, true):
                return Text("Log Meal and \(bolusString)")
            case (true, true, false):
                return Text("Log Carbs and \(bolusString)")
            case (true, false, true):
                return Text("Log FPU and \(bolusString)")
            case (true, false, false):
                return Text(state.externalInsulin ? "Log External Insulin" : "Enact Bolus")
            case (false, true, true):
                return Text("Log Meal")
            case (false, true, false):
                return Text("Log Carbs")
            case (false, false, true):
                return Text("Log FPU")
            default:
                return Text("Continue Without Treatment")
            }
        }

        private var pumpBolusLimitExceeded: Bool {
            !state.externalInsulin && state.amount > state.maxBolus
        }

        private var externalBolusLimitExceeded: Bool {
            state.externalInsulin && state.amount > state.maxExternal
        }

        private var carbLimitExceeded: Bool {
            (state.carbs + state.scannedCarbs) > state.maxCarbs
        }

        private var fatLimitExceeded: Bool {
            (state.fat + state.scannedFat) > state.maxFat
        }

        private var proteinLimitExceeded: Bool {
            (state.protein + state.scannedProtein) > state.maxProtein
        }

        private var limitExceeded: Bool {
            pumpBolusLimitExceeded || externalBolusLimitExceeded || carbLimitExceeded || fatLimitExceeded || proteinLimitExceeded
        }

        private var disableTaskButton: Bool {
            (
                state.isBolusInProgress && state
                    .amount > 0 && !state
                    .externalInsulin &&
                    (
                        state.carbs == 0 && state.scannedCarbs == 0 || state.fat == 0 && state.scannedFat == 0 || state
                            .protein == 0 && state.scannedProtein == 0
                    )
            ) || state
                .addButtonPressed || limitExceeded
        }
    }

    struct DividerDouble: View {
        var body: some View {
            VStack(spacing: 2) {
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(.gray.opacity(0.65))
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(.gray.opacity(0.65))
            }
            .frame(height: 4)
            .padding(.vertical)
        }
    }

    struct DividerCustom: View {
        var body: some View {
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.gray.opacity(0.65))
                .padding(.vertical)
        }
    }

    /// A compact row view for displaying food search results
    struct FoodSearchResultRow: View {
        let item: BarcodeScanner.FoodItem
        let onAdd: () -> Void

        var body: some View {
            Button(action: onAdd) {
                HStack(spacing: 12) {
                    // Product image
                    productImage
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Product info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            if let brand = item.brand {
                                Text(brand)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            if let carbs = item.nutriments.carbohydratesPer100g {
                                Text("\(carbs, specifier: "%.1f")g carbs/100g")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }

                    Spacer()

                    // Add button indicator
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }

        @ViewBuilder private var productImage: some View {
            switch item.imageSource {
            case let .url(url):
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        imagePlaceholder
                    default:
                        ProgressView()
                            .frame(width: 44, height: 44)
                    }
                }

            case let .image(uiImage):
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()

            case .none:
                imagePlaceholder
            }
        }

        private var imagePlaceholder: some View {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.2))
                .overlay(
                    Image(systemName: "fork.knife")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                )
        }
    }
}
