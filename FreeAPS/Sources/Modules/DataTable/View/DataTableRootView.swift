import CoreData
import SwiftUI
import Swinject

extension DataTable {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @State private var isRemoveCarbsAlertPresented = false
        @State private var removeCarbsAlert: Alert?
        @State private var isRemoveInsulinAlertPresented = false
        @State private var removeInsulinAlert: Alert?
        @State private var newGlucose = false

        @Environment(\.colorScheme) var colorScheme

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
                trailing: state.mode == .glucose ? EditButton().asAny() : EmptyView().asAny()
            )
            .popup(isPresented: newGlucose, alignment: .top, direction: .bottom) {
                VStack(spacing: 20) {
                    HStack {
                        Text("New Glucose")
                        DecimalTextField(" ... ", value: $state.manualGlcuose, formatter: glucoseFormatter)
                        Text(state.units.rawValue)
                    }.padding(.horizontal, 20)
                    HStack {
                        let limitLow: Decimal = state.units == .mmolL ? 2.2 : 40
                        let limitHigh: Decimal = state.units == .mmolL ? 21 : 380
                        Button { newGlucose = false }
                        label: { Text("Cancel") }.frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            state.addManualGlucose()
                            newGlucose = false
                        }
                        label: { Text("Save") }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        // .disabled(state.manualGlcuose < limitLow || state.manualGlcuose > limitHigh)

                    }.padding(20)
                }
                .frame(maxHeight: 140)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(colorScheme == .dark ? UIColor.systemGray2 : UIColor.systemGray6))
                )
            }
        }

        private var treatmentsList: some View {
            List {
                ForEach(state.treatments) { item in
                    treatmentView(item)
                }
            }
        }

        private var glucoseList: some View {
            List {
                Button { newGlucose = true }
                label: { Text("Add") }.frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 20)

                ForEach(state.glucose) { item in
                    glucoseView(item)
                }.onDelete(perform: deleteGlucose)
            }
        }

        @ViewBuilder private func treatmentView(_ item: Treatment) -> some View {
            HStack {
                Image(systemName: "circle.fill").foregroundColor(item.color)
                Text(dateFormatter.string(from: item.date))
                    .moveDisabled(true)
                Text(item.type.name)
                Text(item.amountText).foregroundColor(.secondary)
                if let duration = item.durationText {
                    Text(duration).foregroundColor(.secondary)
                }

                if item.type == .carbs {
                    if item.note != "" {
                        Spacer()
                        Text(item.note ?? "").foregroundColor(.brown)
                    }
                    Spacer()
                    Image(systemName: "xmark.circle").foregroundColor(.secondary)
                        .contentShape(Rectangle())
                        .padding(.vertical)
                        .onTapGesture {
                            removeCarbsAlert = Alert(
                                title: Text("Delete carbs?"),
                                message: Text(item.amountText),
                                primaryButton: .destructive(
                                    Text("Delete"),
                                    action: { state.deleteCarbs(item) }
                                ),
                                secondaryButton: .cancel()
                            )
                            isRemoveCarbsAlertPresented = true
                        }
                        .alert(isPresented: $isRemoveCarbsAlertPresented) {
                            removeCarbsAlert!
                        }
                }

                if item.type == .fpus {
                    Spacer()
                    Image(systemName: "xmark.circle").foregroundColor(.secondary)
                        .contentShape(Rectangle())
                        .padding(.vertical)
                        .onTapGesture {
                            removeCarbsAlert = Alert(
                                title: Text("Delete carb equivalents?"),
                                message: Text(""), // Temporary fix. New to fix real amount of carb equivalents later
                                primaryButton: .destructive(
                                    Text("Delete"),
                                    action: { state.deleteCarbs(item) }
                                ),
                                secondaryButton: .cancel()
                            )
                            isRemoveCarbsAlertPresented = true
                        }
                        .alert(isPresented: $isRemoveCarbsAlertPresented) {
                            removeCarbsAlert!
                        }
                }

                if item.type == .bolus {
                    Spacer()
                    Image(systemName: "xmark.circle").foregroundColor(.secondary)
                        .contentShape(Rectangle())
                        .padding(.vertical)
                        .onTapGesture {
                            removeInsulinAlert = Alert(
                                title: Text("Delete insulin?"),
                                message: Text(item.amountText),
                                primaryButton: .destructive(
                                    Text("Delete"),
                                    action: { state.deleteInsulin(item) }
                                ),
                                secondaryButton: .cancel()
                            )
                            isRemoveInsulinAlertPresented = true
                        }
                        .alert(isPresented: $isRemoveInsulinAlertPresented) {
                            removeInsulinAlert!
                        }
                }
            }
        }

        @ViewBuilder private func glucoseView(_ item: Glucose) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(dateFormatter.string(from: item.glucose.dateString))
                    Spacer()
                    Text(item.glucose.glucose.map {
                        glucoseFormatter.string(from: Double(
                            state.units == .mmolL ? $0.asMmolL : Decimal($0)
                        ) as NSNumber)!
                    } ?? "--")
                    Text(state.units.rawValue)
                    Text(item.glucose.direction?.symbol ?? "--")
                }
                Text("ID: " + item.glucose.id).font(.caption2).foregroundColor(.secondary)
            }
        }

        private func deleteGlucose(at offsets: IndexSet) {
            state.deleteGlucose(at: offsets[offsets.startIndex])
        }
    }
}
