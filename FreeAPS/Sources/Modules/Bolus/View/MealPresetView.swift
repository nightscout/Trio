import CoreData
import Foundation
import SwiftUI

struct MealPresetView: View {
    @StateObject var state: Bolus.StateModel
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @Environment(\.managedObjectContext) var moc

    @State private var showAlert = false
    @State private var dish: String = ""
    @State private var saved: Bool = false

    @State private var addNewPreset: Bool = false

    @State private var presetCarbs: Decimal = 0
    @State private var presetFat: Decimal = 0
    @State private var presetProtein: Decimal = 0

    @State private var carbs: Decimal = 0
    @State private var fat: Decimal = 0
    @State private var protein: Decimal = 0

    @FetchRequest(
        entity: MealPresetStored.entity(),
        sortDescriptors: [NSSortDescriptor(key: "dish", ascending: true)]
    ) var carbPresets: FetchedResults<MealPresetStored>

    private var mealFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
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
        NavigationStack {
            Form {
                if addNewPreset {
                    showNewPresetForm()
                } else {
                    addNewPresetButton
                    mealPresets
                    dishInfos()
                    addPresetToTreatmentsButton
                }
            }
            .scrollContentBackground(.hidden).background(color)
            .navigationTitle("Meal Presets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(content: {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        addNewPreset ? (addNewPreset = false) : dismiss()
                    } label: {
                        Text(addNewPreset ? "Cancel" : "Close")
                    }
                }
            })
            .onDisappear {
                resetValues()
            }
        }
    }

    private var addNewPresetButton: some View {
        Button(action: {
            addNewPreset = true
        }, label: {
            HStack {
                Spacer()
                Text("Add new meal Preset")
                Spacer()
            }
        })
    }

    @ViewBuilder private func showNewPresetForm() -> some View {
        Section {
            TextField("Name Of Dish", text: $dish)
        } header: {
            Text("New Preset")
        }

        Section {
            carbsTextField()

            if state.useFPUconversion {
                proteinAndFat()
            }
        }

        savePresetButton
    }

    @ViewBuilder private func carbsTextField() -> some View {
        HStack {
            Text("Carbs").fontWeight(.semibold)
            Spacer()
            TextFieldWithToolBar(
                text: $presetCarbs,
                placeholder: "0",
                keyboardType: .numberPad,
                numberFormatter: mealFormatter
            )
            Text("g").foregroundColor(.secondary)
        }
    }

    @ViewBuilder private func proteinAndFat() -> some View {
        HStack {
            Text("Fat").foregroundColor(.orange)
            Spacer()
            TextFieldWithToolBar(text: $presetFat, placeholder: "0", keyboardType: .numberPad, numberFormatter: mealFormatter)
            Text("g").foregroundColor(.secondary)
        }
        HStack {
            Text("Protein").foregroundColor(.red)
            Spacer()
            TextFieldWithToolBar(
                text: $presetProtein,
                placeholder: "0",
                keyboardType: .numberPad,
                numberFormatter: mealFormatter
            )
            Text("g").foregroundColor(.secondary)
        }
    }

    private var mealPresets: some View {
        Section {
            HStack {
                if state.selection != nil {
                    minusButton
                }
                Picker("Preset", selection: $state.selection) {
                    Text("Saved Food").tag(nil as MealPresetStored?)
                    ForEach(carbPresets, id: \.self) { (preset: MealPresetStored) in
                        Text(preset.dish ?? "").tag(preset as MealPresetStored?)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .center)
                ._onBindingChange($state.selection) { _ in
                    carbs += ((state.selection?.carbs ?? 0) as NSDecimalNumber) as Decimal
                    fat += ((state.selection?.fat ?? 0) as NSDecimalNumber) as Decimal
                    protein += ((state.selection?.protein ?? 0) as NSDecimalNumber) as Decimal
                    state.addToSummation()
                }
                if state.selection != nil {
                    plusButton
                }
            }

            HStack {
                Spacer()

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
                            if let selection = state.selection {
                                let previousSelection = state.selection
                                let count = state.summation.filter { $0 == selection.dish }.count
                                state.summation.removeAll { $0 == selection.dish }
                                carbs -= (((selection.carbs ?? 0) as NSDecimalNumber) as Decimal) * Decimal(count)
                                fat -= (((selection.fat ?? 0) as NSDecimalNumber) as Decimal) * Decimal(count)
                                protein -= (((selection.protein ?? 0) as NSDecimalNumber) as Decimal) * Decimal(count)
                                state.deletePreset()
                                state.selection = previousSelection
                            }
                        }
                    }
                )

                Spacer()
            }
        }
    }

    private var savePresetButton: some View {
        Button {
            saved = true
            if dish != "", saved {
                let preset = MealPresetStored(context: moc)
                preset.dish = dish
                preset.fat = presetFat as NSDecimalNumber
                preset.protein = presetProtein as NSDecimalNumber
                preset.carbs = presetCarbs as NSDecimalNumber
                if self.moc.hasChanges {
                    try? moc.save()
                }
                resetValues()
                saved = false
                addNewPreset = false
            }
        }
        label: {
            Text("Save")
                .font(.headline)
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .disabled(notEnoughPresetInfosGiven)
        .listRowBackground(notEnoughPresetInfosGiven ? Color(.systemGray3) : Color(.systemBlue))
        .shadow(radius: 3)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var addPresetToTreatmentsButton: some View {
        Button {
            state.carbs += carbs
            state.fat += fat
            state.protein += protein

            dismiss()
        }
        label: {
            Text("Add to treatments")
                .font(.headline)
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .disabled(noPresetChosen)
        .listRowBackground(noPresetChosen ? Color(.systemGray3) : Color(.systemBlue))
        .shadow(radius: 3)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var noPresetChosen: Bool {
        state.selection == nil || carbs == 0 || fat == 0 || protein == 0
    }

    private var notEnoughPresetInfosGiven: Bool {
        state
            .useFPUconversion ? (presetCarbs <= 0 && presetFat <= 0 && presetProtein <= 0 || dish == "") :
            (presetCarbs <= 0 || dish == "")
    }

    @ViewBuilder private func dishInfos() -> some View {
        if !state.summation.isEmpty {
            let presetSummary = generatePresetSummary()

            Section(header: Text("Summary")) {
                presetSummary
                    .lineLimit(nil) // In case the text is too long, allow it to wrap to the next line

                LazyVGrid(columns: [
                    GridItem(.flexible(), alignment: .leading),
                    GridItem(.flexible(), alignment: .trailing)
                ], spacing: 0) {
                    Group {
                        Text("Carbs: ")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 2) {
                            Text("\(carbs as NSNumber, formatter: mealFormatter)")
                                .font(.footnote)
                            Text(" g")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Group {
                        Text("Fat: ")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 2) {
                            Text("\(fat as NSNumber, formatter: mealFormatter)")
                                .font(.footnote)
                            Text(" g")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Group {
                        Text("Protein: ")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 2) {
                            Text("\(protein as NSNumber, formatter: mealFormatter)")
                                .font(.footnote)
                            Text(" g")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

//    @ViewBuilder private func dishInfos() -> some View {
//        if !state.summation.isEmpty {
//            let presetSummary = generatePresetSummary()
//
//            Section(header: Text("Summary")) {
//                presetSummary
//                    .lineLimit(nil) // In case the text is too long, allow it to wrap to the next line
//
//                VStack(alignment: .leading) {
//                    HStack {
//                        Text("Carbs: ")
//                            .font(.footnote)
//                            .foregroundStyle(.secondary)
//                        Text("\(carbs as NSNumber, formatter: mealFormatter)")
//                            .font(.footnote)
//                        Text(" g")
//                            .font(.footnote)
//                            .foregroundStyle(.secondary)
//                    }
//
//                    HStack {
//                        Text("Fat: ")
//                            .font(.footnote)
//                            .foregroundStyle(.secondary)
//                        Text("\(fat as NSNumber, formatter: mealFormatter)")
//                            .font(.footnote)
//                        Text(" g")
//                            .font(.footnote)
//                            .foregroundStyle(.secondary)
//                    }
//
//                    HStack {
//                        Text("Protein: ")
//                            .font(.footnote)
//                            .foregroundStyle(.secondary)
//                        Text("\(protein as NSNumber, formatter: mealFormatter)")
//                            .font(.footnote)
//                        Text(" g")
//                            .font(.footnote)
//                            .foregroundStyle(.secondary)
//                    }
//                }
//            }
//        }
//    }

    private func generatePresetSummary() -> some View {
        var counts = [String: Int]()

        for preset in state.summation {
            counts[preset, default: 0] += 1
        }

        return VStack(alignment: .leading) {
            ForEach(counts.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                if value > 0 {
                    HStack {
                        Text("\(value) x")
                            .foregroundColor(.blue)
                        Text(key)
                    }
                }
            }
        }
    }

    private func resetValues() {
        dish = ""
        presetCarbs = 0
        presetFat = 0
        presetProtein = 0
        state.selection = nil
        state.summation.removeAll()
    }

    private var minusButton: some View {
        Button {
            if carbs != 0 {
                carbs -= (((state.selection?.carbs ?? 0) as NSDecimalNumber) as Decimal)
            } else { carbs = 0 }

            if fat != 0,
               (fat - (((state.selection?.fat ?? 0) as NSDecimalNumber) as Decimal) as Decimal) >= 0
            {
                fat -= (((state.selection?.fat ?? 0) as NSDecimalNumber) as Decimal)
            } else { fat = 0 }

            if protein != 0,
               (protein - (((state.selection?.protein ?? 0) as NSDecimalNumber) as Decimal) as Decimal) >= 0
            {
                protein -= (((state.selection?.protein ?? 0) as NSDecimalNumber) as Decimal)
            } else { protein = 0 }

            state.removePresetFromNewMeal()
            if carbs == 0, fat == 0, protein == 0 { state.summation = [] }
        }
        label: { Image(systemName: "minus.circle.fill")
            .font(.system(size: 20))
        }
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
            carbs += ((state.selection?.carbs ?? 0) as NSDecimalNumber) as Decimal
            fat += ((state.selection?.fat ?? 0) as NSDecimalNumber) as Decimal
            protein += ((state.selection?.protein ?? 0) as NSDecimalNumber) as Decimal

            state.addPresetToNewMeal()
        }
        label: { Image(systemName: "plus.circle.fill")
            .font(.system(size: 20))
        }
        .disabled(state.selection == nil)
        .buttonStyle(.borderless)
        .tint(.blue)
    }
}
