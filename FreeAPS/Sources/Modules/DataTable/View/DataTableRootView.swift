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
        @State private var alertTreatmentToDelete: Treatment?
        @State private var alertGlucoseToDelete: Glucose?

        @State private var showExternalInsulin: Bool = false
        @State private var showFutureEntries: Bool = false // default to hide future entries
        @State private var showManualGlucose: Bool = false
        @State private var isAmountUnconfirmed: Bool = true

        @Environment(\.colorScheme) var colorScheme

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
            VStack {
                Picker("Mode", selection: $state.mode) {
                    ForEach(
                        Mode.allCases.filter({ state.historyLayout == .twoTabs ? $0 != .meals : true }).indexed(),
                        id: \.1
                    ) { index, item in
                        if state.historyLayout == .threeTabs && item == .treatments {
                            Text("Insulin")
                                .tag(index)
                        } else {
                            Text(item.name)
                                .tag(index)
                        }
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)

                Form {
                    switch state.mode {
                    case .treatments: treatmentsList
                    case .glucose: glucoseList
                    case .meals: state.historyLayout == .threeTabs ? AnyView(mealsList) : AnyView(EmptyView())
                    }
                }.scrollContentBackground(.hidden)
                    .background(color)
            }.background(color)
                .onAppear(perform: configureView)
                .navigationTitle("History")
                 .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        switch state.mode {
                        case .treatments: addButton({
                                showExternalInsulin = true
                                state.externalInsulinDate = Date()
                            })
                        case .meals: EmptyView()
                        case .glucose: addButton({
                                showManualGlucose = true
                                state.manualGlucose = 0
                            })
                        }
                    }
                }
                .sheet(isPresented: $showManualGlucose) {
                    addGlucoseView()
                }
                .sheet(isPresented: $showExternalInsulin, onDismiss: { if isAmountUnconfirmed { state.externalInsulinAmount = 0
                    state.externalInsulinDate = Date() } }) {
                    addExternalInsulinView()
                }
        }

        @ViewBuilder func addButton(_ action: @escaping () -> Void) -> some View {
            Button(
                action: action,
                label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20))
                }
            )
        }

        private var treatmentsList: some View {
            List {
                HStack {
                    if state.historyLayout == .twoTabs {
                        Text("Insulin").foregroundStyle(.secondary)
                        Spacer()
                        filterEntriesButton
                    } else {
                        Text("Insulin").foregroundStyle(.secondary)
                        Spacer()
                        Text("Time").foregroundStyle(.secondary)
                    }
                }
                if !state.treatments.isEmpty {
                    ForEach(state.treatments.filter({ !showFutureEntries ? $0.date <= Date() : true })) { item in
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
                if !state.meals.isEmpty {
                    ForEach(state.meals.filter({ !showFutureEntries ? $0.date <= Date() : true })) { item in
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
                if !state.glucose.isEmpty {
                    ForEach(state.glucose) { item in
                        glucoseView(item, isManual: item.glucose)
                    }
                } else {
                    HStack {
                        Text("No data.")
                    }
                }
            }.listRowBackground(Color.chart)
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
                                DecimalTextField(
                                    " ... ",
                                    value: $state.manualGlucose,
                                    formatter: manualGlucoseFormatter,
                                    autofocus: true,
                                    cleanInput: true
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

        @ViewBuilder private func treatmentView(_ item: Treatment) -> some View {
            HStack {
                Image(systemName: "circle.fill").foregroundColor(item.color)
                Text((item.isSMB ?? false) ? "SMB" : item.type.name)
                Text(item.amountText).foregroundColor(.secondary)

                if let duration = item.durationText {
                    Text(duration).foregroundColor(.secondary)
                }
                Spacer()
                Text(dateFormatter.string(from: item.date))
                    .moveDisabled(true)
            }
            .swipeActions {
                Button(
                    "Delete",
                    systemImage: "trash.fill",
                    role: .none,
                    action: {
                        alertTreatmentToDelete = item

                        if item.type == .carbs {
                            alertTitle = "Delete Carbs?"
                            alertMessage = dateFormatter.string(from: item.date) + ", " + item.amountText
                        } else if item.type == .fpus {
                            alertTitle = "Delete Carb Equivalents?"
                            alertMessage = "All FPUs of the meal will be deleted."
                        } else {
                            // item is insulin treatment; item.type == .bolus
                            alertTitle = "Delete Insulin?"
                            alertMessage = dateFormatter.string(from: item.date) + ", " + item.amountText

                            if item.isSMB ?? false {
                                // Add text snippet, so that alert message is more descriptive for SMBs
                                alertMessage += "SMB"
                            }
                        }

                        isRemoveHistoryItemAlertPresented = true
                    }
                ).tint(.red)
            }
            .disabled(item.type == .tempBasal || item.type == .tempTarget || item.type == .resume || item.type == .suspend)
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

                    if state.historyLayout == .twoTabs, treatmentToDelete.type == .carbs || treatmentToDelete.type == .fpus {
                        state.deleteCarbs(treatmentToDelete)
                    } else {
                        state.deleteInsulin(treatmentToDelete)
                    }
                }
            } message: {
                Text("\n" + NSLocalizedString(alertMessage, comment: ""))
            }
        }

        @ViewBuilder private func mealView(_ meal: Treatment) -> some View {
            HStack {
                Image(systemName: "circle.fill").foregroundColor(meal.color)
                Text(meal.type.name)
                Text(meal.amountText).foregroundColor(.secondary)

                if let duration = meal.durationText {
                    Text(duration).foregroundColor(.secondary)
                }

                Spacer()

                Text(dateFormatter.string(from: meal.date))
                    .moveDisabled(true)
            }.swipeActions {
                Button(
                    "Delete",
                    systemImage: "trash.fill",
                    role: .none,
                    action: {
                        alertTreatmentToDelete = meal

                        if meal.type == .carbs {
                            alertTitle = "Delete Carbs?"
                            alertMessage = dateFormatter.string(from: meal.date) + ", " + meal.amountText
                        } else if meal.type == .fpus {
                            alertTitle = "Delete Carb Equivalents?"
                            alertMessage = "All FPUs of the meal will be deleted."
                        } else {
                            // item is insulin treatment; item.type == .bolus
                            alertTitle = "Delete Insulin?"
                            alertMessage = dateFormatter.string(from: meal.date) + ", " + meal.amountText
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
                    guard let treatmentToDelete = alertTreatmentToDelete else {
                        debug(.default, "Cannot gracefully unwrap alertTreatmentToDelete!")
                        return
                    }

                    state.deleteCarbs(treatmentToDelete)
                }
            } message: {
                Text("\n" + NSLocalizedString(alertMessage, comment: ""))
            }
        }

        @ViewBuilder func addExternalInsulinView() -> some View {
            NavigationView {
                VStack {
                    Form {
                        Section {
                            HStack {
                                Text("Amount")
                                Spacer()
                                DecimalTextField(
                                    "0",
                                    value: $state.externalInsulinAmount,
                                    formatter: insulinFormatter,
                                    autofocus: true,
                                    cleanInput: true
                                )
                                Text("U").foregroundColor(.secondary)
                            }
                        }.listRowBackground(Color.chart)

                        Section {
                            DatePicker("Date", selection: $state.externalInsulinDate, in: ...Date())
                        }.listRowBackground(Color.chart)

                        let amountWarningCondition = (state.externalInsulinAmount > state.maxBolus)

                        var listBackgroundColor: Color {
                            if amountWarningCondition {
                                return Color.red
                            } else if state.externalInsulinAmount <= 0 || state.externalInsulinAmount > state.maxBolus * 3 {
                                return Color(.systemGray4)
                            } else {
                                return Color(.systemBlue)
                            }
                        }

                        var foregroundColor: Color {
                            if amountWarningCondition {
                                return Color.white
                            } else if state.externalInsulinAmount <= 0 || state.externalInsulinAmount > state.maxBolus * 3 {
                                return Color.secondary
                            } else {
                                return Color.white
                            }
                        }

                        Section {
                            HStack {
                                Button {
                                    state.addExternalInsulin()
                                    isAmountUnconfirmed = false
                                    showExternalInsulin = false
                                }
                                label: {
                                    Text("Log external insulin")
                                }
                                .foregroundStyle(foregroundColor)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .disabled(
                                    state.externalInsulinAmount <= 0 || state.externalInsulinAmount > state.maxBolus * 3
                                )
                            }
                        }
                        header: {
                            if amountWarningCondition
                            {
                                Text("⚠️ Warning! The entered insulin amount is greater than your Max Bolus setting!")
                            }
                        }
                        .listRowBackground(listBackgroundColor).tint(.white)
                    }.scrollContentBackground(.hidden).background(color)
                }
                .onAppear(perform: configureView)
                .navigationTitle("External Insulin")
                 .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") {
                            showExternalInsulin = false
                            state.externalInsulinAmount = 0
                        }
                    }
                }
            }
        }

        @ViewBuilder private func glucoseView(_ item: Glucose, isManual: BloodGlucose) -> some View {
            HStack {
                Text(item.glucose.glucose.map {
                    (
                        isManual.type == GlucoseType.manual.rawValue ?
                            manualGlucoseFormatter :
                            glucoseFormatter
                    )
                    .string(from: Double(
                        state.units == .mmolL ? $0.asMmolL : Decimal($0)
                    ) as NSNumber)!
                } ?? "--")
                if isManual.type == GlucoseType.manual.rawValue {
                    Image(systemName: "drop.fill").symbolRenderingMode(.monochrome).foregroundStyle(.red)
                } else {
                    Text(item.glucose.direction?.symbol ?? "--")
                }
                Spacer()

                Text(dateFormatter.string(from: item.glucose.dateString))
            }
            .swipeActions {
                Button(
                    "Delete",
                    systemImage: "trash.fill",
                    role: .none,
                    action: {
                        alertGlucoseToDelete = item
                        let valueText = (
                            isManual.type == GlucoseType.manual.rawValue ?
                                manualGlucoseFormatter :
                                glucoseFormatter
                        ).string(from: Double(
                            state.units == .mmolL ? Double(item.glucose.value.asMmolL) : item.glucose.value
                        ) as NSNumber)! + " " + state.units.rawValue
                        alertTitle = "Delete Glucose?"
                        alertMessage = dateFormatter.string(from: item.glucose.dateString) + ", " + valueText
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
                        print("Cannot unwrap alertTreatmentToDelete!")
                        return
                    }
                    state.deleteGlucose(glucoseToDelete)
                }
            } message: {
                Text("\n" + NSLocalizedString(alertMessage, comment: ""))
            }
        }
    }
}
