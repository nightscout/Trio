import CoreData
import SwiftUI
import Swinject

extension DataTable {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @State private var isRemoveHistoryItemAlertPresented: Bool = false
        @State private var alertTitle: String = ""
        @State private var alertMessage: String = ""
        @State private var alertTreatmentToDelete: PumpEventStored?
        @State private var alertCarbEntryToDelete: CarbEntryStored?
        @State private var alertGlucoseToDelete: GlucoseStored?

        @State private var showFutureEntries: Bool = false // default to hide future entries
        @State private var showManualGlucose: Bool = false
        @State private var isAmountUnconfirmed: Bool = true

        @State private var showAlert = false

        @Environment(\.colorScheme) var colorScheme
        @Environment(\.managedObjectContext) var context

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
            predicate: NSPredicate.predicateForOneDayAgo,
            animation: .bouncy
        ) var carbEntryStored: FetchedResults<CarbEntryStored>

        private var insulinFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        private var glucoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal

            if state.units == .mmolL {
                formatter.maximumFractionDigits = 1
                formatter.minimumFractionDigits = 1
                formatter.roundingMode = .halfUp
            } else {
                formatter.maximumFractionDigits = 0
            }
            return formatter
        }

        private var manualGlucoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            if state.units == .mmolL {
                formatter.maximumFractionDigits = 1
                formatter.minimumFractionDigits = 1
                formatter.roundingMode = .ceiling
            } else {
                formatter.maximumFractionDigits = 0
            }
            return formatter
        }

        private var dateFormatter: DateFormatter {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter
        }

        private var numberFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        private var color: LinearGradient {
            colorScheme == .dark ? LinearGradient(
                gradient: Gradient(colors: [
                    Color.bgDarkBlue,
                    Color.bgDarkerDarkBlue
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
                :
                LinearGradient(
                    gradient: Gradient(colors: [Color.gray.opacity(0.1)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
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
                        }
                    }.scrollContentBackground(.hidden)
                        .background(color)
                }.blur(radius: state.waitForSuggestion ? 8 : 0)

                if state.waitForSuggestion {
                    CustomProgressView(text: progressText.rawValue)
                }
            })
                .background(color)
                .onAppear(perform: configureView)
                .onDisappear {
                    state.carbEntryDeleted = false
                    state.insulinEntryDeleted = false
                }
                .navigationTitle("History")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        addButton({
                            showManualGlucose = true
                            state.manualGlucose = 0
                        })
                    }
                }
                .sheet(isPresented: $showManualGlucose) {
                    addGlucoseView()
                }
        }

        @ViewBuilder func addButton(_ action: @escaping () -> Void) -> some View {
            Button(
                action: action,
                label: {
                    HStack {
                        Text("Add Glucose")
                        Image(systemName: "plus")
                            .font(.system(size: 20))
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
                    HStack {
                        Text("No data.")
                    }
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
                    HStack {
                        Text("No data.")
                    }
                }
            }.listRowBackground(Color.chart)
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
                                Text("\(glucose.direction ?? "--")")
                            }

                            Spacer()

                            Text(dateFormatter.string(from: glucose.date ?? Date()))
                        }.swipeActions {
                            Button(
                                "Delete",
                                systemImage: "trash.fill",
                                role: .none,
                                action: {
                                    alertGlucoseToDelete = glucose

                                    alertTitle = "Delete Glucose?"
                                    alertMessage = dateFormatter
                                        .string(from: glucose.date ?? Date()) + ", " +
                                        (numberFormatter.string(for: glucose.glucose) ?? "0")

                                    isRemoveHistoryItemAlertPresented = true
                                }
                            ).tint(.red)
                        }
                        .alert(
                            Text(NSLocalizedString(alertTitle, comment: "")),
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
                            Text("\n" + NSLocalizedString(alertMessage, comment: ""))
                        }
                    }
                } else {
                    HStack {
                        Text("No data.")
                    }
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
            let limitLow: Decimal = state.units == .mmolL ? 0.8 : 14
            let limitHigh: Decimal = state.units == .mmolL ? 40 : 720

            NavigationView {
                VStack {
                    Form {
                        Section {
                            HStack {
                                Text("New Glucose")
                                TextFieldWithToolBar(
                                    text: $state.manualGlucose,
                                    placeholder: " ... ",
                                    numberFormatter: manualGlucoseFormatter
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
                    }.scrollContentBackground(.hidden).background(color)
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
                    Text((insulinFormatter.string(from: amount) ?? "0") + NSLocalizedString(" U", comment: "Insulin unit"))
                        .foregroundColor(.secondary)
                    if bolus.isExternal {
                        Text(NSLocalizedString("External", comment: "External Insulin")).foregroundColor(.secondary)
                    }
                } else if let tempBasal = item.tempBasal, let rate = tempBasal.rate {
                    Image(systemName: "circle.fill").foregroundColor(Color.insulin.opacity(0.4))
                    Text("Temp Basal")
                    Text(
                        (insulinFormatter.string(from: rate) ?? "0") +
                            NSLocalizedString(" U/hr", comment: "Unit insulin per hour")
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
                Text(dateFormatter.string(from: item.timestamp ?? Date())).moveDisabled(true)
            }
            .swipeActions {
                if item.bolus != nil {
                    Button(
                        "Delete",
                        systemImage: "trash.fill",
                        role: .none,
                        action: {
                            alertTreatmentToDelete = item
                            alertTitle = "Delete Insulin?"
                            alertMessage = dateFormatter
                                .string(from: item.timestamp ?? Date()) + ", " +
                                (insulinFormatter.string(from: item.bolus?.amount ?? 0) ?? "0") +
                                NSLocalizedString(" U", comment: "Insulin unit")

                            if let bolus = item.bolus {
                                // Add text snippet, so that alert message is more descriptive for SMBs
                                alertMessage += bolus.isSMB ? " SMB" : ""
                            }

                            isRemoveHistoryItemAlertPresented = true
                        }
                    ).tint(.red)
                }
            }
            .alert(
                Text(NSLocalizedString(alertTitle, comment: "")),
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
                Text("\n" + NSLocalizedString(alertMessage, comment: ""))
            }
        }

        @ViewBuilder private func mealView(_ meal: CarbEntryStored) -> some View {
            HStack {
                if meal.isFPU {
                    Image(systemName: "circle.fill").foregroundColor(Color.orange.opacity(0.5))
                    Text("Fat / Protein")
                    Text((numberFormatter.string(for: meal.carbs) ?? "0") + NSLocalizedString(" g", comment: "gram of carbs"))
                } else {
                    Image(systemName: "circle.fill").foregroundColor(Color.loopYellow)
                    Text("Carbs")
                    Text(
                        (numberFormatter.string(for: meal.carbs) ?? "0") +
                            NSLocalizedString(" g", comment: "gram of carb equilvalents")
                    )
                }

                Spacer()

                Text(dateFormatter.string(from: meal.date ?? Date()))
                    .moveDisabled(true)
            }
            .swipeActions {
                Button(
                    "Delete",
                    systemImage: "trash.fill",
                    role: .none,
                    action: {
                        alertCarbEntryToDelete = meal

                        if !meal.isFPU {
                            alertTitle = "Delete Carbs?"
                            alertMessage = dateFormatter
                                .string(from: meal.date ?? Date()) + ", " + (numberFormatter.string(for: meal.carbs) ?? "0") +
                                NSLocalizedString(" g", comment: "gram of carbs")
                        } else {
                            alertTitle = "Delete Carb Equivalents?"
                            alertMessage = "All FPUs of the meal will be deleted."
                        }

                        isRemoveHistoryItemAlertPresented = true
                    }
                ).tint(.red)
            }
            .alert(
                Text(NSLocalizedString(alertTitle, comment: "")),
                isPresented: $isRemoveHistoryItemAlertPresented
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    guard let carbEntryToDelete = alertCarbEntryToDelete else {
                        debug(.default, "Cannot gracefully unwrap alertCarbEntryToDelete!")
                        return
                    }
                    let treatmentObjectID = carbEntryToDelete.objectID

                    state.invokeCarbDeletionTask(treatmentObjectID)
                }
            } message: {
                Text("\n" + NSLocalizedString(alertMessage, comment: ""))
            }
        }

        // MARK: - Format glucose

        private func formatGlucose(_ value: Decimal, isManual: Bool) -> String {
            let formatter = isManual ? manualGlucoseFormatter : glucoseFormatter
            let glucoseValue = state.units == .mmolL ? value.asMmolL : value
            let formattedValue = formatter.string(from: glucoseValue as NSNumber) ?? "--"

            return formattedValue
        }
    }
}
