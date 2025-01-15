//
//  CarbEntryEditorView.swift
//  FreeAPS
//
//  Created by Marvin Polscheit on 15.01.25.
//
import SwiftUI

struct CarbEntryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    var state: DataTable.StateModel
    let carbEntry: CarbEntryStored

    @State private var editedCarbs: Decimal
    @State private var editedFat: Decimal
    @State private var editedProtein: Decimal
    @State private var editedNote: String
    @State private var isFPU: Bool

    init(state: DataTable.StateModel, carbEntry: CarbEntryStored) {
        self.state = state
        self.carbEntry = carbEntry
        _editedCarbs = State(initialValue: Decimal(carbEntry.carbs))
        _editedFat = State(initialValue: 0) // gets updated in the task block
        _editedProtein = State(initialValue: 0) // gets updated in the task block
        _editedNote = State(initialValue: carbEntry.note ?? "")
        _isFPU = State(initialValue: carbEntry.isFPU)
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
                    let treatmentObjectID = carbEntry.objectID

                    state.updateEntry(
                        treatmentObjectID,
                        newCarbs: editedCarbs,
                        newFat: editedFat,
                        newProtein: editedProtein,
                        newNote: editedNote
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
                            numberFormatter: Formatter.decimalFormatterWithOneFractionDigit
                        )
                        Text("g").foregroundStyle(.secondary)
                    }

                    if state.settingsManager.settings.useFPUconversion {
                        HStack {
                            Text("Fat")
                            TextFieldWithToolBar(
                                text: $editedFat,
                                placeholder: "0",
                                keyboardType: .numberPad,
                                numberFormatter: Formatter.decimalFormatterWithOneFractionDigit
                            )
                            Text("g").foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("Protein")
                            TextFieldWithToolBar(
                                text: $editedProtein,
                                placeholder: "0",
                                keyboardType: .numberPad,
                                numberFormatter: Formatter.decimalFormatterWithOneFractionDigit
                            )
                            Text("g").foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Image(systemName: "square.and.pencil")
                        TextFieldWithToolBarString(text: $editedNote, placeholder: "Note...", maxLength: 25)
                    }
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
            // TODO: do we still need this, or is grabbing the entire "hold-it-all" entry enough?
            if carbEntry.isFPU {
                if let originalEntryID = await state.getZeroCarbNonFPUEntry(carbEntry.objectID) {
                    let context = CoreDataStack.shared.persistentContainer.viewContext

                    await context.perform {
                        do {
                            if let originalEntry = try context.existingObject(with: originalEntryID) as? CarbEntryStored {
                                editedFat = Decimal(originalEntry.fat)
                                editedProtein = Decimal(originalEntry.protein)
                                editedNote = originalEntry.note ?? ""
                            }
                        } catch {
                            debugPrint(
                                "\(DebuggingIdentifiers.failed) Failed to fetch original entry: \(error.localizedDescription)"
                            )
                        }
                    }
                } else {
                    debugPrint("\(DebuggingIdentifiers.failed) No original entry ID found")
                }
            }
        }
    }
}
