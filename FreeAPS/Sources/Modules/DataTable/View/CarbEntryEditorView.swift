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

    @State private var editedAmount: Decimal
    @State private var editedFat: Decimal
    @State private var editedProtein: Decimal
    @State private var editedNote: String
    @State private var isFPU: Bool

    init(state: DataTable.StateModel, carbEntry: CarbEntryStored) {
        self.state = state
        self.carbEntry = carbEntry
        _editedAmount = State(initialValue: Decimal(carbEntry.carbs))
        _editedFat = State(initialValue: 0) // gets updated in the task block
        _editedProtein = State(initialValue: 0) // gets updated in the task block
        _editedNote = State(initialValue: carbEntry.note ?? "")
        _isFPU = State(initialValue: carbEntry.isFPU)
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    if isFPU {
                        HStack {
                            Text("Fat")
                            TextFieldWithToolBar(
                                text: $editedFat,
                                placeholder: "Enter fat",
                                numberFormatter: Formatter.integerFormatter
                            )
                            Text("g").foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("Protein")
                            TextFieldWithToolBar(
                                text: $editedProtein,
                                placeholder: "Enter protein",
                                numberFormatter: Formatter.integerFormatter
                            )
                            Text("g").foregroundStyle(.secondary)
                        }
                    } else {
                        HStack {
                            Text("Amount")
                            TextFieldWithToolBar(
                                text: $editedAmount,
                                placeholder: "Enter carbs",
                                numberFormatter: Formatter.decimalFormatterWithOneFractionDigit
                            )
                            Text("g").foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Text("Note")
                        TextField("Optional note", text: $editedNote)
                    }
                }.listRowBackground(Color.chart)

                Section {
                    HStack {
                        Spacer()
                        Button("Save") {
                            let treatmentObjectID = carbEntry.objectID

                            if isFPU {
                                state.updateFPUEntry(
                                    treatmentObjectID,
                                    newFat: editedFat,
                                    newProtein: editedProtein,
                                    newNote: editedNote
                                )
                            } else {
                                state.updateCarbEntry(
                                    treatmentObjectID,
                                    newAmount: editedAmount,
                                    newNote: editedNote
                                )
                            }
                            dismiss()
                        }
                        Spacer()
                    }
                }
                .listRowBackground(Color(.systemBlue))
                .tint(.white)
            }
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Edit Carbs")
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
