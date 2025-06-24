import CoreData
import SwiftUI
import Swinject

extension DataTable {
    struct RootView: BaseView {
        let resolver: Resolver

        @State var state = StateModel()

        @State private var isRemoveHistoryItemAlertPresented: Bool = false
        @State private var alertTitle: String = ""
        @State private var alertMessage: String = ""
        @State private var alertTreatmentToDelete: PumpEventStored?
        @State private var alertCarbEntryToDelete: CarbEntryStored?
        @State private var alertGlucoseToDelete: GlucoseStored?
        @State private var showAlert = false
        @State private var showFutureEntries: Bool = false // default to hide future entries
        @State private var showManualGlucose: Bool = false
        @State private var isAmountUnconfirmed: Bool = true

        @Environment(\.colorScheme) var colorScheme
        @Environment(\.managedObjectContext) var context
        @Environment(AppState.self) var appState

        @FetchRequest(
            entity: GlucoseStored.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \GlucoseStored.date, ascending: false)],
            predicate: NSPredicate.predicateForOneDayAgo,
            animation: .bouncy
        ) var glucoseStored: FetchedResults<GlucoseStored>

        @FetchRequest(
            entity: PumpEventStored.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \PumpEventStored.timestamp, ascending: false)],
            predicate: NSPredicate.pumpHistoryLast24h,
            animation: .bouncy
        ) var pumpEventStored: FetchedResults<PumpEventStored>

        @FetchRequest(
            entity: CarbEntryStored.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \CarbEntryStored.date, ascending: false)],
            predicate: NSPredicate.carbsHistory,
            animation: .bouncy
        ) var carbEntryStored: FetchedResults<CarbEntryStored>

        @FetchRequest(
            entity: OverrideRunStored.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \OverrideRunStored.startDate, ascending: false)],
            predicate: NSPredicate.overridesRunStoredFromOneDayAgo,
            animation: .bouncy
        ) var overrideRunStored: FetchedResults<OverrideRunStored>

        @FetchRequest(
            entity: TempTargetRunStored.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \TempTargetRunStored.startDate, ascending: false)],
            predicate: NSPredicate.tempTargetRunStoredFromOneDayAgo,
            animation: .bouncy
        ) var tempTargetRunStored: FetchedResults<TempTargetRunStored>

        private var manualGlucoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            if state.units == .mgdL {
                formatter.maximumIntegerDigits = 3
                formatter.maximumFractionDigits = 0
            } else {
                formatter.maximumIntegerDigits = 2
                formatter.minimumFractionDigits = 0
                formatter.maximumFractionDigits = 1
            }
            formatter.roundingMode = .halfUp
            return formatter
        }

        var body: some View {
            ZStack(alignment: .center, content: {
                VStack {
                    Picker("Mode", selection: $state.mode) {
                        ForEach(
                            Mode.allCases.indexed(),
                            id: \.1
                        ) { index, item in
                            Text(item.name).tag(index)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)

                    Form {
                        switch state.mode {
                        case .treatments: treatmentsList
                        case .glucose: glucoseList
                        case .meals: mealsList
                        case .adjustments: adjustmentsList
                        }
                    }.scrollContentBackground(.hidden)
                        .background(appState.trioBackgroundColor(for: colorScheme))
                }.blur(radius: state.waitForSuggestion ? 8 : 0)

                // Show custom progress view
                /// don't show it if glucose is stale as it will block the UI
                if state.waitForSuggestion && state.isGlucoseDataFresh(glucoseStored.first?.date) {
                    CustomProgressView(text: progressText.displayName)
                }
            })
                .background(appState.trioBackgroundColor(for: colorScheme))
                .onAppear(perform: configureView)
                .onDisappear {
                    state.carbEntryDeleted = false
                    state.insulinEntryDeleted = false
                }
                .navigationTitle("History")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing, content: {
                        addButton({
                            showManualGlucose = true
                            state.manualGlucose = 0
                        })
                    })
                }
                .sheet(isPresented: $showManualGlucose) {
                    addGlucoseView()
                }
                .sheet(isPresented: $state.showCarbEntryEditor) {
                    if let carbEntry = state.carbEntryToEdit {
                        CarbEntryEditorView(state: state, carbEntry: carbEntry)
                    }
                }
        }

        @ViewBuilder func addButton(_ action: @escaping () -> Void) -> some View {
            Button(
                action: action,
                label: {
                    HStack {
                        Text("Add Glucose")
                        Image(systemName: "plus")
                            .font(.title2)
                    }
                }
            )
        }

        private var progressText: ProgressText {
            switch (state.carbEntryDeleted, state.insulinEntryDeleted) {
            case (true, false):
                return .updatingCOB
            case(false, true):
                return .updatingIOB
            default:
                return .updatingHistory
            }
        }

        private var logGlucoseButton: some View {
            Button(
                action: {
                    showManualGlucose = true
                    state.manualGlucose = 0
                },
                label: {
                    Text("Log Glucose")
                        .foregroundColor(Color.accentColor)
                    Image(systemName: "plus")
                        .foregroundColor(Color.accentColor)
                }
            ).buttonStyle(.borderless)
        }

        private var treatmentsList: some View {
            List {
                HStack {
                    Text("Insulin").foregroundStyle(.secondary)
                    Spacer()
                    Text("Time").foregroundStyle(.secondary)
                }
                if !pumpEventStored.isEmpty {
                    ForEach(pumpEventStored.filter({ !showFutureEntries ? $0.timestamp ?? Date() <= Date() : true })) { item in
                        treatmentView(item)
                    }
                } else {
                    ContentUnavailableView(
                        "No data.",
                        systemImage: "syringe"
                    )
                }
            }.listRowBackground(Color.chart)
        }

        private var mealsList: some View {
            List {
                HStack {
                    Text("Type").foregroundStyle(.secondary)
                    Spacer()
                    filterEntriesButton
                }
                if !carbEntryStored.isEmpty {
                    ForEach(carbEntryStored.filter({ !showFutureEntries ? $0.date ?? Date() <= Date() : true })) { item in
                        mealView(item)
                    }
                } else {
                    ContentUnavailableView(
                        "No data.",
                        systemImage: "fork.knife"
                    )
                }
            }.listRowBackground(Color.chart)
        }

        private var adjustmentsList: some View {
            List {
                HStack {
                    Text("Adjustment").foregroundStyle(.secondary)
                    Spacer()
                }
                if !combinedAdjustments.isEmpty {
                    ForEach(combinedAdjustments) { item in
                        adjustmentView(for: item)
                    }
                } else {
                    ContentUnavailableView(
                        "No data.",
                        systemImage: "clock.arrow.2.circlepath"
                    )
                }
            }
            .listRowBackground(Color.chart)
        }

        private var combinedAdjustments: [AdjustmentItem] {
            let overrides = overrideRunStored.map { override -> AdjustmentItem in
                AdjustmentItem(
                    id: override.objectID,
                    name: override.name ?? String(localized: "Override"),
                    startDate: override.startDate ?? Date(),
                    endDate: override.endDate ?? Date(),
                    target: override.target?.decimalValue,
                    type: .override
                )
            }

            let tempTargets = tempTargetRunStored.map { tempTarget -> AdjustmentItem in
                AdjustmentItem(
                    id: tempTarget.objectID,
                    name: tempTarget.name ?? String(localized: "Temp Target"),
                    startDate: tempTarget.startDate ?? Date(),
                    endDate: tempTarget.endDate ?? Date(),
                    target: tempTarget.target?.decimalValue,
                    type: .tempTarget
                )
            }

            let combined = overrides + tempTargets
            return combined.sorted {
                if $0.startDate == $1.startDate {
                    return $0.endDate > $1.endDate
                }
                return $0.startDate > $1.startDate
            } }

        private struct AdjustmentItem: Identifiable {
            let id: NSManagedObjectID
            let name: String
            let startDate: Date
            let endDate: Date
            let target: Decimal?
            let type: AdjustmentType
        }

        private enum AdjustmentType {
            case override
            case tempTarget

            var symbolName: String {
                switch self {
                case .override:
                    return "clock.arrow.2.circlepath"
                case .tempTarget:
                    return "target"
                }
            }

            var symbolColor: Color {
                switch self {
                case .override:
                    return .orange
                case .tempTarget:
                    return .blue
                }
            }
        }

        @ViewBuilder private func adjustmentView(for item: AdjustmentItem) -> some View {
            let formattedDates =
                "\(Formatter.dateFormatter.string(from: item.startDate)) - \(Formatter.dateFormatter.string(from: item.endDate))"

            let targetDescription: String = {
                guard let target = item.target, target != 0 else {
                    return ""
                }
                return "\(state.units == .mgdL ? target : target.asMmolL) \(state.units.rawValue)"
            }()

            let labels: [String] = [
                targetDescription,
                formattedDates
            ].filter { !$0.isEmpty }

            ZStack(alignment: .trailing) {
                HStack {
                    VStack(alignment: .leading) {
                        HStack {
                            Image(systemName: item.type.symbolName)
                                .foregroundStyle(item.type == .override ? Color.purple : Color.green)
                            Text(item.name)
                                .font(.headline)
                            Spacer()
                        }
                        HStack(spacing: 5) {
                            ForEach(labels, id: \.self) { label in
                                Text(label)
                                if label != labels.last {
                                    Divider()
                                }
                            }
                            Spacer()
                        }
                        .padding(.top, 2)
                        .foregroundColor(.secondary)
                        .font(.caption)
                    }
                    .contentShape(Rectangle())
                }
            }
            .padding(.vertical, 8)
        }

        private var glucoseList: some View {
            List {
                HStack {
                    Text("Values").foregroundStyle(.secondary)
                    Spacer()
                    Text("Time").foregroundStyle(.secondary)
                }
                if !glucoseStored.isEmpty {
                    ForEach(glucoseStored) { glucose in
                        HStack {
                            Text(formatGlucose(Decimal(glucose.glucose), isManual: glucose.isManual))

                            /// check for manual glucose
                            if glucose.isManual {
                                Image(systemName: "drop.fill").symbolRenderingMode(.monochrome).foregroundStyle(.red)
                            } else {
                                Text("\(glucose.directionEnum?.symbol ?? "--")")
                            }

                            Spacer()

                            Text(Formatter.dateFormatter.string(from: glucose.date ?? Date()))
                        }.swipeActions {
                            Button(
                                "Delete",
                                systemImage: "trash.fill",
                                role: .none,
                                action: {
                                    alertGlucoseToDelete = glucose

                                    let glucoseToDisplay = state.units == .mgdL ? glucose.glucose
                                        .description : Int(glucose.glucose).formattedAsMmolL
                                    alertTitle = String(localized: "Delete Glucose?", comment: "Alert title for deleting glucose")
                                    alertMessage = Formatter.dateFormatter
                                        .string(from: glucose.date ?? Date()) + ", " + glucoseToDisplay + " " + state.units
                                        .rawValue

                                    isRemoveHistoryItemAlertPresented = true
                                }
                            ).tint(.red)
                        }
                        .alert(
                            Text(alertTitle),
                            isPresented: $isRemoveHistoryItemAlertPresented
                        ) {
                            Button("Cancel", role: .cancel) {}
                            Button("Delete", role: .destructive) {
                                guard let glucoseToDelete = alertGlucoseToDelete else {
                                    debug(.default, "Cannot gracefully unwrap alertCarbEntryToDelete!")
                                    return
                                }
                                let glucoseToDeleteObjectID = glucoseToDelete.objectID
                                state.invokeGlucoseDeletionTask(glucoseToDeleteObjectID)
                            }
                        } message: {
                            Text("\n" + alertMessage)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No data.",
                        systemImage: "drop.fill"
                    )
                }
            }.listRowBackground(Color.chart)
                .alert(isPresented: $showAlert) {
                    Alert(title: Text("Error"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
                }
        }

        private func deleteGlucose(at offsets: IndexSet) {
            for index in offsets {
                let glucoseToDelete = glucoseStored[index]
                context.delete(glucoseToDelete)
            }

            do {
                try context.save()
                debugPrint("Data Table Root View: \(#function) \(DebuggingIdentifiers.succeeded) deleted glucose from core data")
            } catch {
                debugPrint(
                    "Data Table Root View: \(#function) \(DebuggingIdentifiers.failed) error while deleting glucose from core data"
                )
                alertMessage = "Failed to delete glucose data: \(error.localizedDescription)"
                showAlert = true
            }
        }

        @ViewBuilder private func addGlucoseView() -> some View {
            let limitLow: Decimal = state.units == .mgdL ? Decimal(14) : 14.asMmolL
            let limitHigh: Decimal = state.units == .mgdL ? Decimal(720) : 720.asMmolL

            NavigationView {
                VStack {
                    Form {
                        Section {
                            HStack {
                                Text("New Glucose")
                                TextFieldWithToolBar(
                                    text: $state.manualGlucose,
                                    placeholder: " ... ",
                                    keyboardType: state.units == .mgdL ? .numberPad : .decimalPad,
                                    numberFormatter: manualGlucoseFormatter,
                                    initialFocus: true
                                )
                                Text(state.units.rawValue).foregroundStyle(.secondary)
                            }
                        }.listRowBackground(Color.chart)

                        Section {
                            HStack {
                                Button {
                                    state.addManualGlucose()
                                    isAmountUnconfirmed = false
                                    showManualGlucose = false
                                    state.mode = .glucose
                                }
                                label: { Text("Save") }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .disabled(state.manualGlucose < limitLow || state.manualGlucose > limitHigh)
                            }
                        }
                        .listRowBackground(
                            state.manualGlucose < limitLow || state
                                .manualGlucose > limitHigh ? Color(.systemGray4) : Color(.systemBlue)
                        )
                        .tint(.white)
                    }.scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
                }
                .onAppear(perform: configureView)
                .navigationTitle("Add Glucose")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") {
                            showManualGlucose = false
                        }
                    }
                }
            }
        }

        private var filterEntriesButton: some View {
            Button(action: { showFutureEntries.toggle() }, label: {
                HStack {
                    Text(showFutureEntries ? "Hide Future" : "Show Future")
                        .foregroundColor(Color.secondary)
                    Image(systemName: showFutureEntries ? "calendar.badge.minus" : "calendar.badge.plus")
                }.frame(maxWidth: .infinity, alignment: .trailing)
            }).buttonStyle(.borderless)
        }

        @ViewBuilder private func treatmentView(_ item: PumpEventStored) -> some View {
            HStack {
                if let bolus = item.bolus, let amount = bolus.amount {
                    Image(systemName: "circle.fill").foregroundColor(Color.insulin)
                    Text(bolus.isSMB ? "SMB" : item.type ?? "Bolus")
                    Text(
                        (Formatter.decimalFormatterWithTwoFractionDigits.string(from: amount) ?? "0") +
                            String(localized: " U", comment: "Insulin unit")
                    )
                    .foregroundColor(.secondary)
                    if bolus.isExternal {
                        Text(String(localized: "External", comment: "External Insulin")).foregroundColor(.secondary)
                    }
                } else if let tempBasal = item.tempBasal, let rate = tempBasal.rate {
                    Image(systemName: "circle.fill").foregroundColor(Color.insulin.opacity(0.4))
                    Text("Temp Basal")
                    Text(
                        (Formatter.decimalFormatterWithTwoFractionDigits.string(from: rate) ?? "0") +
                            String(localized: " U/hr", comment: "Unit insulin per hour")
                    )
                    .foregroundColor(.secondary)
                    if tempBasal.duration > 0 {
                        Text("\(tempBasal.duration.string) min").foregroundColor(.secondary)
                    }
                } else {
                    Image(systemName: "circle.fill").foregroundColor(Color.loopGray)
                    Text(item.type ?? "Pump Event")
                }
                Spacer()
                Text(Formatter.dateFormatter.string(from: item.timestamp ?? Date())).moveDisabled(true)
            }
            .swipeActions {
                if item.bolus != nil {
                    Button(
                        "Delete",
                        systemImage: "trash.fill",
                        role: .none,
                        action: {
                            alertTreatmentToDelete = item
                            alertTitle = String(localized: "Delete Insulin?", comment: "Alert title for deleting insulin")
                            alertMessage = Formatter.dateFormatter
                                .string(from: item.timestamp ?? Date()) + ", " +
                                (Formatter.decimalFormatterWithTwoFractionDigits.string(from: item.bolus?.amount ?? 0) ?? "0") +
                                String(localized: " U", comment: "Insulin unit")

                            if let bolus = item.bolus {
                                // Add text snippet, so that alert message is more descriptive for SMBs
                                alertMessage += bolus.isSMB ? String(
                                    localized: " SMB",
                                    comment: "Super Micro Bolus indicator in delete alert"
                                )
                                    : ""
                            }

                            isRemoveHistoryItemAlertPresented = true
                        }
                    ).tint(.red)
                }
            }
            .alert(
                Text(alertTitle),
                isPresented: $isRemoveHistoryItemAlertPresented
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    guard let treatmentToDelete = alertTreatmentToDelete else {
                        debug(.default, "Cannot gracefully unwrap alertTreatmentToDelete!")
                        return
                    }
                    let treatmentObjectID = treatmentToDelete.objectID

                    state.invokeInsulinDeletionTask(treatmentObjectID)
                }
            } message: {
                Text("\n" + alertMessage)
            }
        }

        @ViewBuilder private func mealView(_ meal: CarbEntryStored) -> some View {
            VStack {
                HStack {
                    if meal.isFPU {
                        Image(systemName: "circle.fill").foregroundColor(Color.orange.opacity(0.5))
                        Text("Fat / Protein")
                        Text(
                            (Formatter.decimalFormatterWithTwoFractionDigits.string(for: meal.carbs) ?? "0") +
                                String(localized: " g", comment: "gram of carbs")
                        )
                    } else {
                        Image(systemName: "circle.fill").foregroundColor(Color.loopYellow)
                        Text("Carbs")
                        Text(
                            (Formatter.decimalFormatterWithTwoFractionDigits.string(for: meal.carbs) ?? "0") +
                                String(localized: " g", comment: "gram of carb equilvalents")
                        )
                    }

                    Spacer()

                    Text(Formatter.dateFormatter.string(from: meal.date ?? Date()))
                        .moveDisabled(true)
                }
                if let note = meal.note, note != "" {
                    HStack {
                        Image(systemName: "square.and.pencil")
                        Text(note)
                        Spacer()
                    }.padding(.top, 5).foregroundColor(.secondary)
                }
            }
            .swipeActions {
                Button(
                    "Delete",
                    systemImage: "trash.fill",
                    role: .none,
                    action: {
                        alertCarbEntryToDelete = meal

                        // meal is carb-only
                        if meal.fpuID == nil {
                            alertTitle = String(localized: "Delete Carbs?", comment: "Alert title for deleting carbs")
                            alertMessage = Formatter.dateFormatter
                                .string(from: meal.date ?? Date()) + ", " +
                                (Formatter.decimalFormatterWithTwoFractionDigits.string(for: meal.carbs) ?? "0") +
                                String(localized: " g", comment: "gram of carbs")
                        }
                        // meal is complex-meal or fpu-only
                        else {
                            alertTitle = meal.isFPU ? String(
                                localized: "Delete Carbs Equivalents?",
                                comment: "Alert title for deleting carb equivalents"
                            )
                                : String(localized: "Delete Carbs?", comment: "Alert title for deleting carbs")
                            alertMessage = String(
                                localized: "All FPUs and the carbs of the meal will be deleted.",
                                comment: "Alert message for meal deletion"
                            )
                        }

                        isRemoveHistoryItemAlertPresented = true
                    }
                ).tint(.red)

                Button(
                    "Edit",
                    systemImage: "pencil",
                    role: .none,
                    action: {
                        state.carbEntryToEdit = meal
                        state.showCarbEntryEditor = true
                    }
                )
                .tint(!state.settingsManager.settings.useFPUconversion && meal.isFPU ? Color(.systemGray4) : Color.blue)
                .disabled(!state.settingsManager.settings.useFPUconversion && meal.isFPU)
            }
            .alert(
                Text(alertTitle),
                isPresented: $isRemoveHistoryItemAlertPresented
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    guard let carbEntryToDelete = alertCarbEntryToDelete else {
                        debug(.default, "Cannot gracefully unwrap alertCarbEntryToDelete!")
                        return
                    }
                    let treatmentObjectID = carbEntryToDelete.objectID

                    state.invokeCarbDeletionTask(
                        treatmentObjectID,
                        isFpuOrComplexMeal: carbEntryToDelete.isFPU || carbEntryToDelete.fat > 0 || carbEntryToDelete.protein > 0
                    )
                }
            } message: {
                Text("\n" + alertMessage)
            }
        }

        // MARK: - Format glucose

        private func formatGlucose(_ value: Decimal, isManual: Bool) -> String {
            let formatter = isManual ? manualGlucoseFormatter : Formatter.glucoseFormatter(for: state.units)
            let glucoseValue = state.units == .mmolL ? value.asMmolL : value
            let formattedValue = formatter.string(from: glucoseValue as NSNumber) ?? "--"

            return formattedValue
        }
    }
}
