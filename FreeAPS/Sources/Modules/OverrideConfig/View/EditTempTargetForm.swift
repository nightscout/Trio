import Foundation
import SwiftUI

struct EditTempTargetForm: View {
    @ObservedObject var tempTarget: TempTargetStored
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    @StateObject var state: OverrideConfig.StateModel

    @State private var name: String
    @State private var target: Decimal
    @State private var duration: Decimal
    @State private var date: Date
    @State private var halfBasalTarget: Decimal
    @State private var percentage: Decimal

    @State private var hasChanges = false
    @State private var showAlert = false
    @State private var isUsingSlider = false

    init(tempTargetToEdit: TempTargetStored, state: OverrideConfig.StateModel) {
        tempTarget = tempTargetToEdit
        _state = StateObject(wrappedValue: state)
        _name = State(initialValue: tempTargetToEdit.name ?? "")
        _target = State(initialValue: tempTargetToEdit.target?.decimalValue ?? 0)
        _duration = State(initialValue: tempTargetToEdit.duration?.decimalValue ?? 0)
        _date = State(initialValue: tempTargetToEdit.date ?? Date())
        _halfBasalTarget = State(initialValue: tempTargetToEdit.halfBasalTarget?.decimalValue ?? 160)

        let normalTarget: Decimal = 100
        if let hbt = tempTargetToEdit.halfBasalTarget?.decimalValue {
            let H = hbt
            let N: Decimal = normalTarget
            var T = tempTargetToEdit.target?.decimalValue ?? 0
            if state.units == .mmolL {
                T = T.asMgdL
            }

            let denominator = H - (2 * N) + T
            if denominator != 0 {
                let ratio = (H - N) / denominator
                _percentage = State(initialValue: ratio * 100)
            } else {
                _percentage = State(initialValue: 100)
            }
        } else {
            _percentage = State(initialValue: 100)
        }
    }

    var color: LinearGradient {
        colorScheme == .dark ? LinearGradient(
            gradient: Gradient(colors: [
                Color.bgDarkBlue,
                Color.bgDarkerDarkBlue
            ]),
            startPoint: .top,
            endPoint: .bottom
        ) :
            LinearGradient(
                gradient: Gradient(colors: [Color.gray.opacity(0.1)]),
                startPoint: .top,
                endPoint: .bottom
            )
    }

    private var formatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }

    private var glucoseFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        if state.units == .mmolL {
            formatter.maximumFractionDigits = 1
        } else {
            formatter.maximumFractionDigits = 0
        }
        formatter.roundingMode = .halfUp
        return formatter
    }

    var body: some View {
        NavigationView {
            Form {
                editTempTarget()

                saveButton

            }.scrollContentBackground(.hidden)
                .background(color)
                .navigationTitle("Edit Temp Target")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(leading: Button("Close") {
                    presentationMode.wrappedValue.dismiss()
                })
                .onDisappear {
                    if !hasChanges {
                        // Reset UI changes
                        resetValues()
                    }
                }
                .alert(isPresented: $state.showInvalidTargetAlert) {
                    Alert(
                        title: Text("Invalid Input"),
                        message: Text("\(state.alertMessage)"),
                        dismissButton: .default(Text("OK")) { state.showInvalidTargetAlert = false }
                    )
                }
        }
    }

    @ViewBuilder private func editTempTarget() -> some View {
        Section {
            VStack {
                TextField("Name", text: $name)
                    .onChange(of: name) { _ in hasChanges = true }
            }
        } header: {
            Text("Name")
        }.listRowBackground(Color.chart)

        if state.computeSliderLow() != state.computeSliderHigh() {
            Section {
                VStack {
                    VStack {
                        Text("\(percentage.formatted(.number.precision(.fractionLength(0)))) % Insulin")
                            .foregroundColor(isUsingSlider ? .orange : Color.tabBar)
                            .font(.largeTitle)

                        Slider(value: Binding(
                            get: {
                                Double(truncating: percentage as NSNumber)
                            },
                            set: { newValue in
                                percentage = Decimal(newValue)
                                hasChanges = true

                                // Calculate the halfBasalTarget based on the new percentage value
                                let ratio = Decimal(Int(percentage) / 100)
                                let normalTarget: Decimal = 100
                                var target: Decimal = target
                                if state.units == .mmolL {
                                    target = target.asMgdL
                                }

                                if ratio != 1 {
                                    let hbtcalc = ((2 * ratio * normalTarget) - normalTarget - (ratio * target)) / (ratio - 1)
                                    halfBasalTarget = hbtcalc
                                } else {
                                    halfBasalTarget = normalTarget
                                }
                            }
                        ), in: Double(state.computeSliderLow()) ... Double(state.computeSliderHigh()), step: 5) {}
                        minimumValueLabel: {
                            Text("\(state.computeSliderLow(), specifier: "%.0f")%")
                        }
                        maximumValueLabel: {
                            Text("\(state.computeSliderHigh(), specifier: "%.0f")%")
                        }
                        onEditingChanged: { editing in
                            isUsingSlider = editing
                            state.halfBasalTarget = Decimal(state.computeHalfBasalTarget())
                        }

                        Divider()
                        Text(
                            state
                                .units == .mgdL ?
                                "Half Basal Exercise Target at: \(halfBasalTarget.formatted(.number.precision(.fractionLength(0)))) mg/dl" :
                                "Half Basal Exercise Target at: \(halfBasalTarget.asMmolL.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))) mmol/L"
                        )
                        .foregroundColor(.secondary)
                        .font(.caption).italic()
                    }
                }
            } header: {
                Text("% Insulin")
            } footer: {
                Text("The Slider values are limited to your Autosens Min and Max Settings!")
            }.listRowBackground(Color.chart)
        }

        Section {
            HStack {
                Text("Target")
                Spacer()
                TextFieldWithToolBar(
                    text: Binding(
                        get: { target },
                        set: {
                            target = $0
                            hasChanges = true
                        }
                    ),
                    placeholder: "0",
                    numberFormatter: glucoseFormatter
                )
                Text(state.units.rawValue).foregroundColor(.secondary)
            }
            HStack {
                Text("Duration")
                Spacer()
                TextFieldWithToolBar(
                    text: Binding(
                        get: { duration },
                        set: {
                            duration = $0
                            hasChanges = true
                        }
                    ),
                    placeholder: "0",
                    numberFormatter: formatter
                )
                Text("minutes").foregroundColor(.secondary)
            }
            DatePicker("Date", selection: $date)
                .onChange(of: date) { _ in hasChanges = true }
        }.listRowBackground(Color.chart)
    }

    private var saveButton: some View {
        HStack {
            Spacer()
            Button(action: {
                if !state.isInputInvalid(target: target) {
                    saveChanges()

                    do {
                        guard let moc = tempTarget.managedObjectContext else { return }
                        guard moc.hasChanges else { return }
                        try moc.save()

                        // Disable previous active Temp Target and update View
                        if let currentActiveTempTarget = state.currentActiveTempTarget {
                            Task {
                                await state.disableAllActiveOverrides(
                                    except: currentActiveTempTarget.objectID,
                                    createOverrideRunEntry: false
                                )

                                state.updateLatestTempTargetConfiguration()
                            }
                        }

                        hasChanges = false
                        presentationMode.wrappedValue.dismiss()
                    } catch {
                        debugPrint("Failed to edit Temp Target")
                    }
                }
            }, label: {
                Text("Save")
            })
                .disabled(!hasChanges)
                .frame(maxWidth: .infinity, alignment: .center)
                .tint(.white)

            Spacer()
        }.listRowBackground(hasChanges ? Color(.systemBlue) : Color(.systemGray4))
    }

    private func saveChanges() {
        tempTarget.name = name
        tempTarget.target = NSDecimalNumber(decimal: target)
        tempTarget.duration = NSDecimalNumber(decimal: duration)
        tempTarget.date = date
        tempTarget.isUploadedToNS = false
        tempTarget.halfBasalTarget = NSDecimalNumber(decimal: halfBasalTarget)
    }

    private func resetValues() {
        name = tempTarget.name ?? ""
        target = tempTarget.target?.decimalValue ?? 0
        duration = tempTarget.duration?.decimalValue ?? 0
        date = tempTarget.date ?? Date()
    }
}
