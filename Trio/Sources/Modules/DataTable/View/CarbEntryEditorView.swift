//
//  CarbEntryEditorView.swift
//  FreeAPS
//
//  Created by Marvin Polscheit on 15.01.25.
//
import CoreData
import SwiftUI

struct CarbEntryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    var state: DataTable.StateModel
    let carbEntry: CarbEntryStored

    /*
     This is the objectID of the entry that the user is editing. It is NOT always the `carbEntry: CarbEntryStored` that we pass to the `CarbEntryEditorView`.
     We need this because FPUs and carbs are treated completely different and that complicates the update process.
     */
    @State private var entryToEdit: NSManagedObjectID?

    @State private var editedCarbs: Decimal
    @State private var editedFat: Decimal
    @State private var editedProtein: Decimal
    @State private var editedNote: String
    @State private var isFPU: Bool
    @State private var editedDate: Date

    init(state: DataTable.StateModel, carbEntry: CarbEntryStored) {
        self.state = state
        self.carbEntry = carbEntry
        _editedCarbs = State(initialValue: 0) // gets updated in the task block
        _editedFat = State(initialValue: 0) // gets updated in the task block
        _editedProtein = State(initialValue: 0) // gets updated in the task block
        _editedNote = State(initialValue: carbEntry.note ?? "")
        _isFPU = State(initialValue: carbEntry.isFPU)
        _entryToEdit = State(initialValue: nil)
        _editedDate = State(initialValue: Date())
    }

    private var mealFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumIntegerDigits = 3
        formatter.maximumFractionDigits = 0
        return formatter
    }

    private var carbLimitExceeded: Bool {
        editedCarbs > state.settingsManager.settings.maxCarbs
    }

    private var fatLimitExceeded: Bool {
        editedFat > state.settingsManager.settings.maxFat
    }

    private var proteinLimitExceeded: Bool {
        editedProtein > state.settingsManager.settings.maxProtein
    }

    private var limitExceeded: Bool {
        carbLimitExceeded || fatLimitExceeded || proteinLimitExceeded
    }

    private var isButtonDisabled: Bool {
        editedCarbs == 0 && editedFat == 0 && editedProtein == 0
    }

    private var buttonLabel: some View {
        if carbLimitExceeded {
            return Text("Max Carbs of \(state.settingsManager.settings.maxCarbs.description) g Exceeded")
        } else if fatLimitExceeded {
            return Text("Max Fat of \(state.settingsManager.settings.maxFat.description) g Exceeded")
        } else if proteinLimitExceeded {
            return Text("Max Protein of \(state.settingsManager.settings.maxProtein.description) g Exceeded")
        }

        return Text("Save and Update")
    }

    private var buttonBackgroundColor: Color {
        var treatmentButtonBackground = Color(.systemBlue)
        if limitExceeded {
            treatmentButtonBackground = Color(.systemRed)
        } else if isButtonDisabled {
            treatmentButtonBackground = Color(.systemGray)
        }

        return treatmentButtonBackground
    }

    var stickyButton: some View {
        ZStack {
            Rectangle()
                .frame(width: UIScreen.main.bounds.width, height: 65)
                .foregroundStyle(colorScheme == .dark ? Color.bgDarkerDarkBlue : Color.white)
                .background(.thinMaterial)
                .opacity(0.8)
                .clipShape(Rectangle())

            Button(
                action: {
                    guard let entryToEdit = entryToEdit else { return }

                    state.updateEntry(
                        entryToEdit,
                        newCarbs: editedCarbs,
                        newFat: editedFat,
                        newProtein: editedProtein,
                        newNote: editedNote,
                        newDate: editedDate
                    )
                    dismiss()
                }, label: {
                    buttonLabel
                        .font(.headline)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(10)
                }
            )
            .frame(width: UIScreen.main.bounds.width * 0.9, height: 40, alignment: .center)
            .disabled(isButtonDisabled)
            .background(buttonBackgroundColor)
            .tint(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack {
                        Text("Carbs")
                        TextFieldWithToolBar(
                            text: $editedCarbs,
                            placeholder: "0",
                            keyboardType: .numberPad,
                            numberFormatter: mealFormatter
                        )
                        Text("g").foregroundStyle(.secondary)
                    }

                    if state.settingsManager.settings.useFPUconversion {
                        HStack {
                            Text("Protein")
                            TextFieldWithToolBar(
                                text: $editedProtein,
                                placeholder: "0",
                                keyboardType: .numberPad,
                                numberFormatter: mealFormatter
                            )
                            Text("g").foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("Fat")
                            TextFieldWithToolBar(
                                text: $editedFat,
                                placeholder: "0",
                                keyboardType: .numberPad,
                                numberFormatter: mealFormatter
                            )
                            Text("g").foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Image(systemName: "square.and.pencil")
                        TextFieldWithToolBarString(text: $editedNote, placeholder: String(localized: "Note..."), maxLength: 25)
                    }
                }.listRowBackground(Color.chart)

                Section {
                    DatePicker(
                        "Time",
                        selection: $editedDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }.listRowBackground(Color.chart)
            }
            .safeAreaInset(
                edge: .bottom,
                spacing: 30
            ) {
                stickyButton
            }
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Edit Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            /*
             User taps on a FPU entry in the DataTable list. There are two cases:
             - the User has entered this FPU entry WITH carbs
             - the User has entered this FPU entry WITHOUT carbs
             In the first case, we simply need to load the corresponding carb entry. For this case THIS is the entry we want to edit.
             In the second case, we need to load the zero-carb entry that actualy holds the FPU values (and the carbs). For this case THIS is the entry we want to edit.
             */
            if carbEntry.isFPU {
                if let result = await state.handleFPUEntry(carbEntry.objectID) {
                    editedCarbs = result.entryValues?.carbs ?? 0
                    editedFat = result.entryValues?.fat ?? 0
                    editedProtein = result.entryValues?.protein ?? 0
                    editedNote = result.entryValues?.note ?? ""
                    entryToEdit = result.entryID
                    editedDate = result.entryValues?.date ?? Date()
                }
                /*
                 User taps on a carb entry in the DataTable list. There are again two cases which don't need explicit handling:
                 - the User has only entered carbs
                 - the User has entered carbs with FPU
                 In both cases, we need to simply load the carb entry that holds all the necessary values for us. This is the entry we want to edit.
                 */
            } else {
                if let values = await state.loadEntryValues(from: carbEntry.objectID) {
                    editedCarbs = values.carbs
                    editedFat = values.fat
                    editedProtein = values.protein
                    editedNote = values.note
                    editedDate = values.date
                    entryToEdit = carbEntry.objectID
                }
            }
        }
    }
}
