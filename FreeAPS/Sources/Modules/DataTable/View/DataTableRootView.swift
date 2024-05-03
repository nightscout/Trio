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
        @State private var showManualGlucose = false
        @State private var showExternalInsulin = false
        @State private var isAmountUnconfirmed = true

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
            formatter.maximumFractionDigits = 0
            if state.units == .mmolL {
                formatter.minimumFractionDigits = 1
                formatter.maximumFractionDigits = 1
            }
            formatter.roundingMode = .halfUp
            return formatter
        }

        private var dateFormatter: DateFormatter {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter
        }

        var body: some View {
            VStack {
                Picker("Mode", selection: $state.mode) {
                    ForEach(Mode.allCases.indexed(), id: \.1) { index, item in
                        Text(item.name).tag(index)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)

                Form {
                    switch state.mode {
                    case .treatments: treatmentsList
                    case .glucose: glucoseList
                    }
                }
            }
            .onAppear(perform: configureView)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarItems(
                leading: Button("Close", action: state.hideModal),
                trailing: state.mode == .glucose ? addGlucoseButton.asAny() : addInsulinButton.asAny()
            )
            .sheet(isPresented: $showExternalInsulin, onDismiss: {
                if isAmountUnconfirmed {
                    state.externalInsulinAmount = 0
                    state.externalInsulinDate = Date()
                }
            }) {
                addExternalInsulinView
            }
            .sheet(isPresented: $showManualGlucose) {
                addGlucoseView
            }
        }

        private var addInsulinButton: some View {
            Button(action: { showExternalInsulin = true
                state.externalInsulinDate = Date() }, label: {
                Text("Add Insulin")
                    .foregroundColor(Color.accentColor)
                Image(systemName: "plus")
                    .foregroundColor(Color.accentColor)
            }).buttonStyle(.borderless)
        }

        private var addGlucoseButton: some View {
            Button(
                action: {
                    showManualGlucose = true
                    state.manualGlucose = 0
                },
                label: {
                    Text("Add Glucose")
                        .foregroundColor(Color.accentColor)
                    Image(systemName: "plus")
                        .foregroundColor(Color.accentColor)
                }
            ).buttonStyle(.borderless)
        }

        private var treatmentsList: some View {
            List {
                if !state.treatments.isEmpty {
                    ForEach(state.treatments) { item in
                        treatmentView(item)
                    }
                } else {
                    HStack {
                        Text("No data.")
                    }
                }
            }
        }

        private var glucoseList: some View {
            List {
                if !state.glucose.isEmpty {
                    ForEach(state.glucose) { item in
                        glucoseView(item)
                    }
                } else {
                    HStack {
                        Text(NSLocalizedString("No data.", comment: "No data text when no entries in history list"))
                    }
                }
            }
        }

        private var addGlucoseView: some View {
            NavigationView {
                VStack {
                    Form {
                        Section {
                            HStack {
                                Text("New Glucose")
                                DecimalTextField(
                                    " ... ",
                                    value: $state.manualGlucose,
                                    formatter: glucoseFormatter,
                                    autofocus: true,
                                    cleanInput: true
                                )
                                Text(state.units.rawValue).foregroundStyle(.secondary)
                            }
                        }

                        Section {
                            HStack {
                                let limitLow: Decimal = state.units == .mmolL ? 0.8 : 40
                                let limitHigh: Decimal = state.units == .mmolL ? 14 : 720

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
                    }
                }
                .onAppear(perform: configureView)
                .navigationTitle("Add Glucose")
                .navigationBarTitleDisplayMode(.automatic)
                .navigationBarItems(leading: Button("Close", action: { showManualGlucose = false }))
            }
        }

        @ViewBuilder private func treatmentView(_ item: Treatment) -> some View {
            HStack {
                if item.type == .bolus || item.type == .carbs {
                    Image(systemName: "circle.fill").foregroundColor(item.color).padding(.vertical)
                } else {
                    Image(systemName: "circle.fill").foregroundColor(item.color)
                }
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
                // Only allow swipe to delete if a carb, fpu, or bolus entry.
                if item.type == .carbs || item.type == .fpus || item.type == .bolus {
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
                                    alertMessage += " SMB"
                                }
                            }

                            isRemoveHistoryItemAlertPresented = true
                        }
                    ).tint(.red)
                }
            }
            .disabled(
                item.type == .tempBasal || item.type == .tempTarget || item.type == .resume || item
                    .type == .suspend
            )
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

                    if treatmentToDelete.type == .carbs || treatmentToDelete.type == .fpus {
                        state.deleteCarbs(treatmentToDelete)
                    } else {
                        state.deleteInsulin(treatmentToDelete)
                    }
                }
            } message: {
                Text("\n" + NSLocalizedString(alertMessage, comment: ""))
            }
        }

        var addExternalInsulinView: some View {
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
                        }

                        Section {
                            DatePicker("Date", selection: $state.externalInsulinDate, in: ...Date())
                        }

                        let amountWarningCondition = (state.externalInsulinAmount > state.maxBolus) &&
                            (state.externalInsulinAmount <= state.maxBolus * 3)

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
                                .foregroundColor(amountWarningCondition ? Color.white : Color.accentColor)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .disabled(
                                    state.externalInsulinAmount <= 0 || state.externalInsulinAmount > state
                                        .maxBolus * 3
                                )
                            }
                        }
                        header: {
                            if amountWarningCondition
                            {
                                Text("⚠️ Warning! The entered insulin amount is greater than your Max Bolus setting!")
                            }
                        }
                        .listRowBackground(
                            amountWarningCondition ? Color
                                .red : colorScheme == .dark ? Color(UIColor.secondarySystemBackground) : Color.white
                        )
                    }
                }
                .onAppear(perform: configureView)
                .navigationTitle("External Insulin")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(leading: Button("Close", action: { showExternalInsulin = false
                    state.externalInsulinAmount = 0 }))
            }
        }

        @ViewBuilder private func glucoseView(_ item: Glucose) -> some View {
            HStack {
                Text(item.glucose.glucose.map {
                    glucoseFormatter.string(from: Double(
                        state.units == .mmolL ? $0.asMmolL : Decimal($0)
                    ) as NSNumber)!
                } ?? "--")
                Text(item.glucose.direction?.symbol ?? "--")
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

                        let valueText = glucoseFormatter.string(from: Double(
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
                    // gracefully unwrap value here.
                    // value cannot ever really be nil because it is an existing(!) table entry
                    // but just to be sure.
                    guard let glucoseToDelete = alertGlucoseToDelete else {
                        print("Cannot gracefully unwrap alertTreatmentToDelete!")
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
