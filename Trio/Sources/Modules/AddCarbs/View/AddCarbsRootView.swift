import CoreData
import SwiftUI
import Swinject

extension AddCarbs {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @State var dish: String = ""
        @State var isPromtPresented = false
        @State var noteSaved = false
        @State var mealSaved = false
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
                if let carbsReq = state.carbsRequired {
                    Section {
                        HStack {
                            Text("Carbs required")
                            Spacer()
                            Text(formatter.string(from: carbsReq as NSNumber)! + " g")
                        }
                    }
                }
                Section {
                    HStack {
                        Text("Carbs").fontWeight(.semibold)
                        Spacer()
                        TextFieldWithToolBar(
                            text: $state.carbs,
                            placeholder: "0",
                            shouldBecomeFirstResponder: true,
                            numberFormatter: formatter
                        )
                        Text(state.carbs > state.maxCarbs ? "⚠️" : "g").foregroundColor(.secondary)
                    }.padding(.vertical)

                    if state.useFPUconversion {
                        proteinAndFat()
                    }
                    VStack {
                        HStack {
                            Text("Note").foregroundColor(.secondary)
                            TextFieldWithToolBarString(text: $state.note, placeholder: "", maxLength: 25)
                            if isFocused {
                                Button { isFocused = false } label: { Image(systemName: "keyboard.chevron.compact.down") }
                                    .controlSize(.mini)
                            }
                        }.focused($isFocused)

                        HStack {
                            Spacer()
                            Text("\(state.note.count) / 25")
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Button {
                            state.useFPUconversion.toggle()
                        }
                        label: {
                            Text(
                                state
                                    .useFPUconversion ? NSLocalizedString("Hide Fat & Protein", comment: "") :
                                    NSLocalizedString("Fat & Protein", comment: "")
                            ) }
                            .controlSize(.mini)
                            .buttonStyle(BorderlessButtonStyle())
                        Button {
                            isPromtPresented = true
                        }
                        label: { Text("Save as Preset") }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .controlSize(.mini)
                            .buttonStyle(BorderlessButtonStyle())
                            .foregroundColor(
                                (state.carbs <= 0 && state.fat <= 0 && state.protein <= 0) ||
                                    (
                                        (((state.selection?.carbs ?? 0) as NSDecimalNumber) as Decimal) == state
                                            .carbs && (((state.selection?.fat ?? 0) as NSDecimalNumber) as Decimal) == state
                                            .fat && (((state.selection?.protein ?? 0) as NSDecimalNumber) as Decimal) ==
                                            state
                                            .protein
                                    ) ? .secondary : .orange
                            )
                            .disabled(
                                (state.carbs <= 0 && state.fat <= 0 && state.protein <= 0) ||
                                    (
                                        (((state.selection?.carbs ?? 0) as NSDecimalNumber) as Decimal) == state
                                            .carbs && (((state.selection?.fat ?? 0) as NSDecimalNumber) as Decimal) == state
                                            .fat && (((state.selection?.protein ?? 0) as NSDecimalNumber) as Decimal) == state
                                            .protein
                                    )
                            )
                    }
                    .popover(isPresented: $isPromtPresented) {
                        presetPopover
                    }
                }

                if state.useFPUconversion {
                    Section {
                        mealPresets
                    }
                }

                Section {
                    DatePicker("Date", selection: $state.date)
                }

                Section {
                    Button {
                        mealSaved = true
                        state.add()
                    }
                    label: { Text(state.saveButtonText()).font(.title3) }
                        .disabled(
                            mealSaved
                                || state.carbs > state.maxCarbs
                                || state.fat > state.maxFat
                                || state.protein > state.maxProtein
                                || (state.carbs <= 0 && state.fat <= 0 && state.protein <= 0)
                        )
                        .foregroundStyle(
                            mealSaved || (state.carbs <= 0 && state.fat <= 0 && state.protein <= 0) ? .gray :
                                state.carbs > state.maxCarbs || state.fat > state.maxFat || state.protein > state
                                .maxProtein ? .red : .blue
                        )
                        .frame(maxWidth: .infinity, alignment: .center)
                } footer: { Text(state.waitersNotepad().description) }

                if !state.useFPUconversion {
                    Section {
                        mealPresets
                    }
                }
            }
            .onAppear(perform: configureView)
            .navigationBarItems(leading: Button("Close", action: state.hideModal))
        }

        var presetPopover: some View {
            Form {
                Section {
                    TextField("Name Of Dish", text: $dish)
                    Button {
                        noteSaved = true
                        if dish != "", noteSaved {
                            let preset = Presets(context: moc)
                            preset.dish = dish
                            preset.fat = state.fat as NSDecimalNumber
                            preset.protein = state.protein as NSDecimalNumber
                            preset.carbs = state.carbs as NSDecimalNumber
                            try? moc.save()
                            state.addNewPresetToWaitersNotepad(dish)
                            noteSaved = false
                            isPromtPresented = false
                        }
                    }
                    label: { Text("Save") }
                    Button {
                        dish = ""
                        noteSaved = false
                        isPromtPresented = false }
                    label: { Text("Cancel") }
                } header: { Text("Enter Meal Preset Name") }
            }
        }

        var mealPresets: some View {
            Section {
                VStack {
                    Picker("Meal Presets", selection: $state.selection) {
                        Text("Empty").tag(nil as Presets?)
                        ForEach(carbPresets, id: \.self) { (preset: Presets) in
                            Text(preset.dish ?? "").tag(preset as Presets?)
                        }
                    }
                    .pickerStyle(.automatic)
                    ._onBindingChange($state.selection) { _ in
                        state.carbs += ((state.selection?.carbs ?? 0) as NSDecimalNumber) as Decimal
                        state.fat += ((state.selection?.fat ?? 0) as NSDecimalNumber) as Decimal
                        state.protein += ((state.selection?.protein ?? 0) as NSDecimalNumber) as Decimal
                        state.addToSummation()
                    }
                }
                HStack {
                    Button("Delete Preset") {
                        showAlert.toggle()
                    }
                    .disabled(state.selection == nil)
                    .accentColor(.orange)
                    .buttonStyle(BorderlessButtonStyle())
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
                    label: { Text("[ -1 ]") }
                        .disabled(
                            state
                                .selection == nil ||
                                (
                                    !state.summation.contains(state.selection?.dish ?? "") && (state.selection?.dish ?? "") != ""
                                )
                        )
                        .buttonStyle(BorderlessButtonStyle())
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .accentColor(.minus)
                    Button {
                        state.carbs += ((state.selection?.carbs ?? 0) as NSDecimalNumber) as Decimal
                        state.fat += ((state.selection?.fat ?? 0) as NSDecimalNumber) as Decimal
                        state.protein += ((state.selection?.protein ?? 0) as NSDecimalNumber) as Decimal

                        state.addPresetToNewMeal()
                    }
                    label: { Text("[ +1 ]") }
                        .disabled(state.selection == nil)
                        .buttonStyle(BorderlessButtonStyle())
                        .accentColor(.blue)
                }
            }
        }

        @ViewBuilder private func proteinAndFat() -> some View {
            HStack {
                Text("Fat").foregroundColor(.orange) // .fontWeight(.thin)
                Spacer()
                TextFieldWithToolBar(text: $state.fat, placeholder: "0", numberFormatter: formatter)
                Text(state.fat > state.maxFat ? "⚠️" : "g").foregroundColor(.secondary)
            }
            HStack {
                Text("Protein").foregroundColor(.red) // .fontWeight(.thin)
                Spacer()
                TextFieldWithToolBar(text: $state.protein, placeholder: "0", numberFormatter: formatter)
                Text(state.protein > state.maxProtein ? "⚠️" : "g").foregroundColor(.secondary)
            }
        }
    }
}
