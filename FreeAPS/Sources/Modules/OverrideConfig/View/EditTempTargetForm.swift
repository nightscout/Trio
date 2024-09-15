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

    @State private var hasChanges = false
    @State private var showAlert = false

    init(tempTargetToEdit: TempTargetStored, state: OverrideConfig.StateModel) {
        tempTarget = tempTargetToEdit
        _state = StateObject(wrappedValue: state)
        _name = State(initialValue: tempTargetToEdit.name ?? "")
        _target = State(initialValue: tempTargetToEdit.target?.decimalValue ?? 0)
        _duration = State(initialValue: tempTargetToEdit.duration?.decimalValue ?? 0)
        _date = State(initialValue: tempTargetToEdit.date ?? Date())
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

                        // Update View
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
    }

    private func resetValues() {
        name = tempTarget.name ?? ""
        target = tempTarget.target?.decimalValue ?? 0
        duration = tempTarget.duration?.decimalValue ?? 0
        date = tempTarget.date ?? Date()
    }
}
