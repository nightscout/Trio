import CoreData
import SwiftUI
import Swinject

extension AddCarbs {
    struct RootView: BaseView {
        let resolver: Resolver
        let editMode: Bool
        let override: Bool
        @StateObject var state = StateModel()
        @State var dish: String = ""
        @State var isPromptPresented = false
        @State var saved = false
        @State var pushed = false
        @State private var showAlert = false
        @FocusState private var isFocused: Bool

        @FetchRequest(
            entity: Presets.entity(),
            sortDescriptors: [NSSortDescriptor(key: "dish", ascending: true)]
        ) var carbPresets: FetchedResults<Presets>

        @Environment(\.managedObjectContext) var moc

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }

        var body: some View {
            Form {
                if let carbsReq = state.carbsRequired, state.carbs < carbsReq {
                    Section {
                        HStack {
                            Text("Carbs required")
                            Spacer()
                            Text((formatter.string(from: carbsReq as NSNumber) ?? "") + " g")
                        }
                    }
                }
                Section {
                    HStack {
                        Text("Carbs").fontWeight(.semibold)
                        Spacer()
                        DecimalTextField(
                            "0",
                            value: $state.carbs,
                            formatter: formatter,
                            autofocus: true,
                            cleanInput: true
                        )
                        Text("grams").foregroundColor(.secondary)
                    }

                    if state.useFPUconversion {
                        proteinAndFat()
                    }

                    // Summary when combining presets
                    if state.waitersNotepad() != "" {
                        HStack {
                            Text("Total")
                            let test = state.waitersNotepad().components(separatedBy: ", ").removeDublicates()
                            HStack(spacing: 0) {
                                ForEach(test, id: \.self) {
                                    Text($0).foregroundStyle(Color.randomGreen()).font(.footnote)
                                    Text($0 == test[test.count - 1] ? "" : ", ")
                                }
                            }.frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }

                    // Time
                    HStack {
                        let now = Date.now
                        Text("Time")
                        Spacer()
                        if !pushed {
                            Button {
                                pushed = true
                            } label: { Text("Now") }.buttonStyle(.borderless).foregroundColor(.secondary).padding(.trailing, 5)
                        } else {
                            Button { state.date = state.date.addingTimeInterval(-15.minutes.timeInterval) }
                            label: { Image(systemName: "minus.circle") }.tint(.blue).buttonStyle(.borderless)
                            DatePicker(
                                "Time",
                                selection: $state.date,
                                displayedComponents: [.hourAndMinute]
                            ).controlSize(.mini)
                                .labelsHidden()
                            Button {
                                state.date = state.date.addingTimeInterval(15.minutes.timeInterval)
                            }
                            label: { Image(systemName: "plus.circle") }.tint(.blue).buttonStyle(.borderless)
                        }
                    }

                    // Optional meal note
                    HStack {
                        Text("Note").foregroundColor(.secondary)
                        TextField("", text: $state.note).multilineTextAlignment(.trailing)
                        if state.note != "", isFocused {
                            Button { isFocused = false } label: { Image(systemName: "keyboard.chevron.compact.down") }
                                .controlSize(.mini)
                        }
                    }
                    .focused($isFocused)
                    .popover(isPresented: $isPromptPresented) {
                        presetPopover
                    }
                }

                Section {
                    Button { state.add(override, fetch: editMode) }
                    label: { Text((state.skipBolus && !override && !editMode) ? "Save" : "Continue") }
                        .disabled(empty)
                        .frame(maxWidth: .infinity, alignment: .center)
                }.listRowBackground(!empty ? Color(.systemBlue) : Color(.systemGray4))
                    .tint(.white)

                Section {
                    mealPresets
                }
            }
            .onAppear {
                configureView {
                    state.loadEntries(editMode)
                }
            }
            .navigationTitle("Add Meal")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Close", action: state.hideModal))
        }

        private var presetPopover: some View {
            Form {
                Section {
                    TextField("Name Of Dish", text: $dish)
                    Button {
                        saved = true
                        if dish != "", saved {
                            let preset = Presets(context: moc)
                            preset.dish = dish
                            preset.fat = state.fat as NSDecimalNumber
                            preset.protein = state.protein as NSDecimalNumber
                            preset.carbs = state.carbs as NSDecimalNumber
                            try? moc.save()
                            state.addNewPresetToWaitersNotepad(dish)
                            saved = false
                            isPromptPresented = false
                        }
                    }
                    label: { Text("Save") }
                    Button {
                        dish = ""
                        saved = false
                        isPromptPresented = false }
                    label: { Text("Cancel") }
                } header: { Text("Enter Meal Preset Name") }
            }
        }

        private var empty: Bool {
            state.carbs <= 0 && state.fat <= 0 && state.protein <= 0
        }

        private var minusButton: some View {
            Button {
                if state.carbs != 0,
                   (state.carbs - (((state.selection?.carbs ?? 0) as NSDecimalNumber) as Decimal) as Decimal) >= 0
                {
                    state.carbs -= (((state.selection?.carbs ?? 0) as NSDecimalNumber) as Decimal)
                } else { state.carbs = 0 }

                if state.fat != 0,
                   (state.fat - (((state.selection?.fat ?? 0) as NSDecimalNumber) as Decimal) as Decimal) >= 0
                {
                    state.fat -= (((state.selection?.fat ?? 0) as NSDecimalNumber) as Decimal)
                } else { state.fat = 0 }

                if state.protein != 0,
                   (state.protein - (((state.selection?.protein ?? 0) as NSDecimalNumber) as Decimal) as Decimal) >= 0
                {
                    state.protein -= (((state.selection?.protein ?? 0) as NSDecimalNumber) as Decimal)
                } else { state.protein = 0 }

                state.removePresetFromNewMeal()
                if state.carbs == 0, state.fat == 0, state.protein == 0 { state.summation = [] }
            }
            label: { Image(systemName: "minus.circle") }
                .disabled(
                    state
                        .selection == nil ||
                        (
                            !state.summation
                                .contains(state.selection?.dish ?? "") && (state.selection?.dish ?? "") != ""
                        )
                )
                .buttonStyle(.borderless)
                .tint(.blue)
        }

        private var plusButton: some View {
            Button {
                state.carbs += ((state.selection?.carbs ?? 0) as NSDecimalNumber) as Decimal
                state.fat += ((state.selection?.fat ?? 0) as NSDecimalNumber) as Decimal
                state.protein += ((state.selection?.protein ?? 0) as NSDecimalNumber) as Decimal

                state.addPresetToNewMeal()
            }
            label: { Image(systemName: "plus.circle") }
                .disabled(state.selection == nil)
                .buttonStyle(.borderless)
                .tint(.blue)
        }

        private var mealPresets: some View {
            Section {
                HStack {
                    if state.selection != nil {
                        minusButton
                    }
                    Picker("Preset", selection: $state.selection) {
                        Text("Saved Food").tag(nil as Presets?)
                        ForEach(carbPresets, id: \.self) { (preset: Presets) in
                            Text(preset.dish ?? "").tag(preset as Presets?)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .center)
                    ._onBindingChange($state.selection) { _ in
                        state.carbs += ((state.selection?.carbs ?? 0) as NSDecimalNumber) as Decimal
                        state.fat += ((state.selection?.fat ?? 0) as NSDecimalNumber) as Decimal
                        state.protein += ((state.selection?.protein ?? 0) as NSDecimalNumber) as Decimal
                        state.addToSummation()
                    }
                    if state.selection != nil {
                        plusButton
                    }
                }

                HStack {
                    Button("Delete Preset") {
                        showAlert.toggle()
                    }
                    .disabled(state.selection == nil)
                    .tint(.orange)
                    .buttonStyle(.borderless)
                    .alert(
                        "Delete preset '\(state.selection?.dish ?? "")'?",
                        isPresented: $showAlert,
                        actions: {
                            Button("No", role: .cancel) {}
                            Button("Yes", role: .destructive) {
                                state.deletePreset()

                                state.carbs += ((state.selection?.carbs ?? 0) as NSDecimalNumber) as Decimal
                                state.fat += ((state.selection?.fat ?? 0) as NSDecimalNumber) as Decimal
                                state.protein += ((state.selection?.protein ?? 0) as NSDecimalNumber) as Decimal

                                state.addPresetToNewMeal()
                            }
                        }
                    )

                    Spacer()

                    Button {
                        isPromptPresented = true
                    }
                    label: { Text("Save as Preset") }
                        .buttonStyle(.borderless)
                        .disabled(
                            empty ||
                                (
                                    (((state.selection?.carbs ?? 0) as NSDecimalNumber) as Decimal) == state
                                        .carbs && (((state.selection?.fat ?? 0) as NSDecimalNumber) as Decimal) == state
                                        .fat && (((state.selection?.protein ?? 0) as NSDecimalNumber) as Decimal) == state
                                        .protein
                                )
                        )
                }
            }
        }

        @ViewBuilder private func proteinAndFat() -> some View {
            HStack {
                Text("Fat").foregroundColor(.orange)
                Spacer()
                DecimalTextField(
                    "0",
                    value: $state.fat,
                    formatter: formatter,
                    autofocus: false,
                    cleanInput: true
                )
                Text("grams").foregroundColor(.secondary)
            }
            HStack {
                Text("Protein").foregroundColor(.red)
                Spacer()
                DecimalTextField(
                    "0",
                    value: $state.protein,
                    formatter: formatter,
                    autofocus: false,
                    cleanInput: true
                ).foregroundColor(.loopRed)

                Text("grams").foregroundColor(.secondary)
            }
        }
    }
}

public extension Color {
    static func randomGreen(randomOpacity: Bool = false) -> Color {
        Color(
            red: .random(in: 0 ... 1),
            green: .random(in: 0.4 ... 0.7),
            blue: .random(in: 0.2 ... 1),
            opacity: randomOpacity ? .random(in: 0.8 ... 1) : 1
        )
    }
}
