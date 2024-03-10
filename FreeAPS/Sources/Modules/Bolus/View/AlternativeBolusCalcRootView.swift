import Charts
import CoreData
import LoopKitUI
import SwiftUI
import Swinject

extension Bolus {
    struct AlternativeBolusCalcRootView: BaseView {
        let resolver: Resolver

        @StateObject var state: StateModel

        @State private var showInfo: Bool = false
        @State private var showAlert = false
        @State private var autofocus: Bool = true
        @State private var calculatorDetent = PresentationDetent.medium
        @State private var pushed: Bool = false
        @State private var isPromptPresented: Bool = false
        @State private var dish: String = ""
        @State private var saved: Bool = false
        @State private var debounce: DispatchWorkItem?

        @Environment(\.managedObjectContext) var moc

        private enum Config {
            static let dividerHeight: CGFloat = 2
            static let spacing: CGFloat = 3
        }

        @Environment(\.colorScheme) var colorScheme

        @FetchRequest(
            entity: Presets.entity(),
            sortDescriptors: [NSSortDescriptor(key: "dish", ascending: true)]
        ) var carbPresets: FetchedResults<Presets>

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        private var mealFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }

        private var gluoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            if state.units == .mmolL {
                formatter.maximumFractionDigits = 1
            } else { formatter.maximumFractionDigits = 0 }
            return formatter
        }

        private var fractionDigits: Int {
            if state.units == .mmolL {
                return 1
            } else { return 0 }
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

        private var empty: Bool {
            state.useFPUconversion ? (state.carbs <= 0 && state.fat <= 0 && state.protein <= 0) : (state.carbs <= 0)
        }

        /// Handles macro input (carb, fat, protein) in a debounced fashion.
        func handleDebouncedInput() {
            debounce?.cancel()
            debounce = DispatchWorkItem { [self] in
                state.insulinCalculated = state.calculateInsulin()
            }
            if let debounce = debounce {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: debounce)
            }
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
                state.carbs += ((state.selection?.carbs ?? 0) as NSDecimalNumber) as Decimal
                state.fat += ((state.selection?.fat ?? 0) as NSDecimalNumber) as Decimal
                state.protein += ((state.selection?.protein ?? 0) as NSDecimalNumber) as Decimal

                state.addPresetToNewMeal()
            }
            label: { Image(systemName: "plus.circle.fill")
                .font(.system(size: 20))
            }
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
                Text("g").foregroundColor(.secondary)
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

                Text("g").foregroundColor(.secondary)
            }
        }

        var body: some View {
            ZStack(alignment: .center) {
                VStack {
                    Form {
                        Section {
                            HStack {
                                Text("Carbs").fontWeight(.semibold)
                                Spacer()
                                DecimalTextField(
                                    "0",
                                    value: $state.carbs,
                                    formatter: formatter,
                                    autofocus: false,
                                    cleanInput: true
                                ).onChange(of: state.carbs) { _ in
                                    if state.carbs > 0 {
                                        handleDebouncedInput()
                                    }
                                }
                                Text("g").foregroundColor(.secondary)
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
                                Text("Time").foregroundStyle(Color.secondary)
                                Spacer()
                                if !pushed {
                                    Button {
                                        pushed = true
                                    } label: { Text("Now") }.buttonStyle(.borderless).foregroundColor(.secondary)
                                        .padding(.trailing, 5)
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

                            .popover(isPresented: $isPromptPresented) {
                                presetPopover
                            }
                        }.listRowBackground(Color.chart)

                        if state.displayPresets {
                            Section {
                                mealPresets
                            }.listRowBackground(Color.chart)
                        }

                        Section {
                            HStack {
                                Button(action: {
                                    showInfo.toggle()
                                }, label: {
                                    Image(systemName: "info.circle")
                                    Text("Calculations")
                                })
                                    .foregroundStyle(.blue)
                                    .font(.footnote)
                                    .buttonStyle(PlainButtonStyle())
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if state.fattyMeals {
                                    Spacer()
                                    Toggle(isOn: $state.useFattyMealCorrectionFactor) {
                                        Text("Fatty Meal")
                                    }
                                    .toggleStyle(CheckboxToggleStyle())
                                    .font(.footnote)
                                    .onChange(of: state.useFattyMealCorrectionFactor) { _ in
                                        state.insulinCalculated = state.calculateInsulin()
                                        if state.useFattyMealCorrectionFactor {
                                            state.useSuperBolus = false
                                        }
                                    }
                                }
                                if state.sweetMeals {
                                    Spacer()
                                    Toggle(isOn: $state.useSuperBolus) {
                                        Text("Super Bolus")
                                    }
                                    .toggleStyle(CheckboxToggleStyle())
                                    .font(.footnote)
                                    .onChange(of: state.useSuperBolus) { _ in
                                        state.insulinCalculated = state.calculateInsulin()
                                        if state.useSuperBolus {
                                            state.useFattyMealCorrectionFactor = false
                                        }
                                    }
                                }
                            }

                            HStack {
                                Text("Recommended Bolus")
                                Spacer()
                                Text(
                                    formatter
                                        .string(from: Double(state.insulinCalculated) as NSNumber) ?? ""
                                )
                                Text(
                                    NSLocalizedString(
                                        " U",
                                        comment: "Unit in number of units delivered (keep the space character!)"
                                    )
                                ).foregroundColor(.secondary)
                            }.contentShape(Rectangle())
                                .onTapGesture { state.amount = state.insulinCalculated }

                            HStack {
                                Text("Bolus")
                                Spacer()
                                DecimalTextField(
                                    "0",
                                    value: $state.amount,
                                    formatter: formatter,
                                    autofocus: false,
                                    cleanInput: true,
                                    textColor: .systemBlue
                                )
                                Text(" U").foregroundColor(.secondary)
                            }

                            if state.amount > 0 {
                                HStack {
                                    Text("External insulin")
                                    Spacer()
                                    Toggle("", isOn: $state.externalInsulin).toggleStyle(Checkbox())
                                }
                            }
                        }.listRowBackground(Color.chart)
                    }
                }.safeAreaInset(edge: .bottom, spacing: 0) {
                    stickyButton
                }.blur(radius: state.waitForSuggestion ? 5 : 0)

                if state.waitForSuggestion {
                    CustomProgressView(text: progressText.rawValue)
                }
            }
            .scrollContentBackground(.hidden).background(color)
            .blur(radius: showInfo ? 3 : 0)
            .navigationTitle("Treatments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(content: {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        state.hideModal()
                    } label: {
                        Text("Close")
                    }
                }
            })
            .onAppear {
                configureView {
                    state.insulinCalculated = state.calculateInsulin()
                }
            }
            .onDisappear {
                state.addButtonPressed = false
            }
            .sheet(isPresented: $showInfo) {
                calculationsDetailView
                    .presentationDetents(
                        [.fraction(0.9), .large],
                        selection: $calculatorDetent
                    )
            }
        }

        var progressText: ProgressText {
            switch (state.amount > 0, state.carbs > 0) {
            case (true, true):
                return .updatingIOBandCOB
            case (false, true):
                return .updatingCOB
            case (true, false):
                return .updatingIOB
            default:
                return .updatingTreatments
            }
        }

        var stickyButton: some View {
            ZStack {
                Rectangle()
                    .frame(width: UIScreen.main.bounds.width, height: 120).offset(y: 40)
                    .shadow(
                        color: colorScheme == .dark ? Color(red: 0.02745098039, green: 0.1098039216, blue: 0.1411764706) :
                            Color.black.opacity(0.33),
                        radius: 3
                    )
                    .foregroundStyle(Color.chart)

                Button {
                    state.invokeTreatmentsTask()
                } label: {
                    taskButtonLabel
                        .font(.headline)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .frame(minHeight: 50)
                }
                .disabled(disableTaskButton)
                .background(
                    (state.externalInsulin ? externalBolusLimit : pumpBolusLimit) ? Color(.systemRed) :
                        Color(.systemBlue)
                )
                .shadow(radius: 3)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding()
                .offset(y: 20)
            }
        }

        var calcSettingsFirstRow: some View {
            GridRow {
                Group {
                    Text("Carb Ratio:")
                        .foregroundColor(.secondary)
                }.gridCellAnchor(.leading)

                Group {
                    Text("ISF:")
                        .foregroundColor(.secondary)
                }.gridCellAnchor(.leading)

                VStack {
                    Text("Target:")
                        .foregroundColor(.secondary)
                }.gridCellAnchor(.leading)
            }
        }

        var calcSettingsSecondRow: some View {
            GridRow {
                Text(state.carbRatio.formatted() + " " + NSLocalizedString("g/U", comment: " grams per Unit"))
                    .gridCellAnchor(.leading)

                Text(
                    state.isf.formatted() + " " + state.units
                        .rawValue + NSLocalizedString("/U", comment: "/Insulin unit")
                ).gridCellAnchor(.leading)
                let target = state.units == .mmolL ? state.target.asMmolL : state.target
                Text(
                    target
                        .formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits))) +
                        " " + state.units.rawValue
                ).gridCellAnchor(.leading)
            }
        }

        var calcGlucoseFirstRow: some View {
            GridRow(alignment: .center) {
                let currentBG = state.units == .mmolL ? state.currentBG.asMmolL : state.currentBG
                let target = state.units == .mmolL ? state.target.asMmolL : state.target

                Text("Glucose:").foregroundColor(.secondary)

                let targetDifference = state.units == .mmolL ? state.targetDifference.asMmolL : state.targetDifference
                let firstRow = currentBG
                    .formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits)))

                    + " - " +
                    target
                    .formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits)))
                    + " = " +
                    targetDifference
                    .formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits)))

                Text(firstRow).frame(minWidth: 0, alignment: .leading).foregroundColor(.secondary)
                    .gridColumnAlignment(.leading)

                HStack {
                    Text(
                        self.insulinRounder(state.targetDifferenceInsulin).formatted()
                    )
                    Text("U").foregroundColor(.secondary)
                }.fontWeight(.bold)
                    .gridColumnAlignment(.trailing)
            }
        }

        var calcGlucoseSecondRow: some View {
            GridRow(alignment: .center) {
                let currentBG = state.units == .mmolL ? state.currentBG.asMmolL : state.currentBG
                Text(
                    currentBG
                        .formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits))) +
                        " " +
                        state.units.rawValue
                )

                let targetDifference = state.units == .mmolL ? state.targetDifference.asMmolL : state.targetDifference
                let secondRow = targetDifference
                    .formatted(
                        .number.grouping(.never).rounded()
                            .precision(.fractionLength(fractionDigits))
                    )
                    + " / " +
                    state.isf.formatted()
                    + " ≈ " +
                    self.insulinRounder(state.targetDifferenceInsulin).formatted()

                Text(secondRow).foregroundColor(.secondary).gridColumnAlignment(.leading)

                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
        }

        var calcGlucoseFormulaRow: some View {
            GridRow(alignment: .top) {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])

                Text("(Current - Target) / ISF").foregroundColor(.secondary.opacity(colorScheme == .dark ? 0.65 : 0.8))
                    .gridColumnAlignment(.leading)
                    .gridCellColumns(2)
            }
            .font(.caption)
        }

        var calcIOBRow: some View {
            GridRow(alignment: .center) {
                HStack {
                    Text("IOB:").foregroundColor(.secondary)
                    Text(
                        self.insulinRounder(state.iob).formatted()
                    )
                }

                Text("Subtract IOB").foregroundColor(.secondary.opacity(colorScheme == .dark ? 0.65 : 0.8)).font(.footnote)

                let iobFormatted = self.insulinRounder(state.iob).formatted()
                HStack {
                    Text((state.iob >= 0 ? "-" : "") + (state.iob >= 0 ? iobFormatted : "(" + iobFormatted + ")"))
                    Text("U").foregroundColor(.secondary)
                }.fontWeight(.bold)
                    .gridColumnAlignment(.trailing)
            }
        }

        var calcCOBRow: some View {
            GridRow(alignment: .center) {
                HStack {
                    Text("COB:").foregroundColor(.secondary)
                    Text(
                        state.wholeCob
                            .formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits))) +
                            NSLocalizedString(" g", comment: "grams")
                    )
                }

                Text(
                    state.wholeCob
                        .formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits)))
                        + " / " +
                        state.carbRatio.formatted()
                        + " ≈ " +
                        self.insulinRounder(state.wholeCobInsulin).formatted()
                )
                .foregroundColor(.secondary)
                .gridColumnAlignment(.leading)

                HStack {
                    Text(
                        self.insulinRounder(state.wholeCobInsulin).formatted()
                    )
                    Text("U").foregroundColor(.secondary)
                }.fontWeight(.bold)
                    .gridColumnAlignment(.trailing)
            }
        }

        var calcCOBFormulaRow: some View {
            GridRow(alignment: .center) {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])

                Text("COB / Carb Ratio").foregroundColor(.secondary.opacity(colorScheme == .dark ? 0.65 : 0.8))
                    .gridColumnAlignment(.leading)
                    .gridCellColumns(2)
            }
            .font(.caption)
        }

        var calcDeltaRow: some View {
            GridRow(alignment: .center) {
                Text("Delta:").foregroundColor(.secondary)

                let deltaBG = state.units == .mmolL ? state.deltaBG.asMmolL : state.deltaBG
                Text(
                    deltaBG
                        .formatted(
                            .number.grouping(.never).rounded()
                                .precision(.fractionLength(fractionDigits))
                        )
                        + " / " +
                        state.isf.formatted()
                        + " ≈ " +
                        self.insulinRounder(state.fifteenMinInsulin).formatted()
                )
                .foregroundColor(.secondary)
                .gridColumnAlignment(.leading)

                HStack {
                    Text(
                        self.insulinRounder(state.fifteenMinInsulin).formatted()
                    )
                    Text("U").foregroundColor(.secondary)
                }.fontWeight(.bold)
                    .gridColumnAlignment(.trailing)
            }
        }

        var calcDeltaFormulaRow: some View {
            GridRow(alignment: .center) {
                let deltaBG = state.units == .mmolL ? state.deltaBG.asMmolL : state.deltaBG
                Text(
                    deltaBG
                        .formatted(
                            .number.grouping(.never).rounded()
                                .precision(.fractionLength(fractionDigits))
                        ) + " " +
                        state.units.rawValue
                )

                Text("15min Delta / ISF").font(.caption).foregroundColor(.secondary.opacity(colorScheme == .dark ? 0.65 : 0.8))
                    .gridColumnAlignment(.leading)
                    .gridCellColumns(2).padding(.top, 5)
            }
        }

        var calcFullBolusRow: some View {
            GridRow(alignment: .center) {
                Text("Full Bolus")
                    .foregroundColor(.secondary)

                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])

                HStack {
                    Text(self.insulinRounder(state.wholeCalc).formatted())
                        .foregroundStyle(state.wholeCalc < 0 ? Color.loopRed : Color.primary)
                    Text("U").foregroundColor(.secondary)
                }.gridColumnAlignment(.trailing)
                    .fontWeight(.bold)
            }
        }

        var calcSuperBolusRow: some View {
            GridRow(alignment: .center) {
                Text("Super Bolus")
                    .foregroundColor(.secondary)

                Text("Added to Result").foregroundColor(.secondary.opacity(colorScheme == .dark ? 0.65 : 0.8)).font(.footnote)

                HStack {
                    Text("+" + self.insulinRounder(state.superBolusInsulin).formatted())
                        .foregroundStyle(Color.loopRed)
                    Text("U").foregroundColor(.secondary)
                }.gridColumnAlignment(.trailing)
                    .fontWeight(.bold)
            }
        }

        var calcResultRow: some View {
            GridRow(alignment: .center) {
                Text("Result").fontWeight(.bold)

                HStack {
                    Text(state.useSuperBolus ? "(" : "")
                        .foregroundColor(.loopRed)

                        + Text(state.fraction.formatted())

                        + Text(" x ")
                        .foregroundColor(.secondary)

                        // if fatty meal is chosen
                        + Text(state.useFattyMealCorrectionFactor ? state.fattyMealFactor.formatted() : "")
                        .foregroundColor(.orange)

                        + Text(state.useFattyMealCorrectionFactor ? " x " : "")
                        .foregroundColor(.secondary)
                        // endif fatty meal is chosen

                        + Text(self.insulinRounder(state.wholeCalc).formatted())
                        .foregroundColor(state.wholeCalc < 0 ? Color.loopRed : Color.primary)

                        // if superbolus is chosen
                        + Text(state.useSuperBolus ? ")" : "")
                        .foregroundColor(.loopRed)

                        + Text(state.useSuperBolus ? " + " : "")
                        .foregroundColor(.secondary)

                        + Text(state.useSuperBolus ? state.superBolusInsulin.formatted() : "")
                        .foregroundColor(.loopRed)
                        // endif superbolus is chosen

                        + Text(" ≈ ")
                        .foregroundColor(.secondary)
                }
                .gridColumnAlignment(.leading)

                HStack {
                    Text(self.insulinRounder(state.insulinCalculated).formatted())
                        .fontWeight(.bold)
                        .foregroundColor(state.wholeCalc >= state.maxBolus ? Color.loopRed : Color.blue)
                    Text("U").foregroundColor(.secondary)
                }
                .gridColumnAlignment(.trailing)
                .fontWeight(.bold)
            }
        }

        var calcResultFormulaRow: some View {
            GridRow(alignment: .bottom) {
                if state.useFattyMealCorrectionFactor {
                    Group {
                        Text("Factor x Fatty Meal Factor x Full Bolus")
                            .foregroundColor(.secondary.opacity(colorScheme == .dark ? 0.65 : 0.8))
                            +
                            Text(state.wholeCalc > state.maxBolus ? " ≈ Max Bolus" : "").foregroundColor(Color.loopRed)
                    }
                    .font(.caption)
                    .gridCellAnchor(.center)
                    .gridCellColumns(3)
                } else if state.useSuperBolus {
                    Group {
                        Text("(Factor x Full Bolus) + Super Bolus")
                            .foregroundColor(.secondary.opacity(colorScheme == .dark ? 0.65 : 0.8))
                            +
                            Text(state.wholeCalc > state.maxBolus ? " ≈ Max Bolus" : "").foregroundColor(Color.loopRed)
                    }
                    .font(.caption)
                    .gridCellAnchor(.center)
                    .gridCellColumns(3)
                } else {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    Group {
                        Text("Factor x Full Bolus")
                            .foregroundColor(.secondary.opacity(colorScheme == .dark ? 0.65 : 0.8))
                            +
                            Text(state.wholeCalc > state.maxBolus ? " ≈ Max Bolus" : "").foregroundColor(Color.loopRed)
                    }
                    .font(.caption)
                    .padding(.top, 5)
                    .gridCellAnchor(.leading)
                    .gridCellColumns(2)
                }
            }
        }

        var calculationsDetailView: some View {
            NavigationStack {
                ScrollView {
                    Grid(alignment: .topLeading, horizontalSpacing: 3, verticalSpacing: 0) {
                        GridRow {
                            Text("Calculations").fontWeight(.bold).gridCellColumns(3).gridCellAnchor(.center).padding(.vertical)
                        }

                        calcSettingsFirstRow
                        calcSettingsSecondRow

                        DividerCustom()

                        // meal entries as grid rows
                        if state.carbs > 0 {
                            GridRow {
                                Text("Carbs").foregroundColor(.secondary)
                                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                                HStack {
                                    Text(state.carbs.formatted())
                                    Text("g").foregroundColor(.secondary)
                                }.gridCellAnchor(.trailing)
                            }
                        }

                        if state.fat > 0 {
                            GridRow {
                                Text("Fat").foregroundColor(.secondary)
                                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                                HStack {
                                    Text(state.fat.formatted())
                                    Text("g").foregroundColor(.secondary)
                                }.gridCellAnchor(.trailing)
                            }
                        }

                        if state.protein > 0 {
                            GridRow {
                                Text("Protein").foregroundColor(.secondary)
                                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                                HStack {
                                    Text(state.protein.formatted())
                                    Text("g").foregroundColor(.secondary)
                                }.gridCellAnchor(.trailing)
                            }
                        }

                        if state.carbs > 0 || state.protein > 0 || state.fat > 0 {
                            DividerCustom()
                        }

                        GridRow {
                            Text("Detailed Calculation Steps").gridCellColumns(3).gridCellAnchor(.center)
                                .padding(.bottom, 10)
                        }
                        calcGlucoseFirstRow
                        calcGlucoseSecondRow.padding(.bottom, 5)
                        calcGlucoseFormulaRow

                        DividerCustom()

                        calcIOBRow

                        DividerCustom()

                        calcCOBRow.padding(.bottom, 5)
                        calcCOBFormulaRow

                        DividerCustom()

                        calcDeltaRow
                        calcDeltaFormulaRow

                        DividerCustom()

                        calcFullBolusRow

                        if state.useSuperBolus {
                            DividerCustom()
                            calcSuperBolusRow
                        }

                        DividerDouble()

                        calcResultRow
                        calcResultFormulaRow
                    }

                    Spacer()

                    Button { showInfo = false }
                    label: { Text("Got it!").frame(maxWidth: .infinity, alignment: .center) }
                        .buttonStyle(.bordered)
                        .padding(.top)
                }
                .padding([.horizontal, .bottom])
                .font(.subheadline)
            }
        }

        private func insulinRounder(_ value: Decimal) -> Decimal {
            let toRound = NSDecimalNumber(decimal: value).doubleValue
            return Decimal(floor(100 * toRound) / 100)
        }

        private var taskButtonLabel: some View {
            let hasInsulin = state.amount > 0
            let hasCarbs = state.carbs > 0
            let hasFatOrProtein = state.fat > 0 || state.protein > 0

            switch (hasInsulin, hasCarbs, hasFatOrProtein) {
            case (true, true, true):
                return Text(
                    state
                        .externalInsulin ? (
                            externalBolusLimit ? "Manual bolus exceeds max bolus!" : "Log meal and external insulin"
                        ) :
                        (pumpBolusLimit ? "Pump bolus exceeds max bolus!" : "Log meal and enact bolus")
                )
            case (true, true, false):
                return Text(
                    state
                        .externalInsulin ?
                        (externalBolusLimit ? "Manual bolus exceeds max bolus!" : "Log carbs and external insulin") :
                        (pumpBolusLimit ? "Pump bolus exceeds max bolus!" : "Log carbs and enact bolus")
                )
            case (true, false, false):
                return Text(
                    state
                        .externalInsulin ? (externalBolusLimit ? "Manual bolus exceeds max bolus!" : "Log external insulin") :
                        (pumpBolusLimit ? "Pump bolus exceeds max bolus!" : "Enact bolus")
                )
            case (false, true, true):
                return Text("Log meal")
            case (false, true, false):
                return Text("Log carbs")
            case (false, false, true):
                return Text("Log FPUs")
            default:
                return Text("Continue without logging treatments")
            }
        }

        private var pumpBolusLimit: Bool {
            state.amount > state.maxBolus
        }

        private var externalBolusLimit: Bool {
            state.amount > state.maxBolus * 3
        }

        private var disableTaskButton: Bool {
            state.amount > 0 ? (state.externalInsulin ? externalBolusLimit : pumpBolusLimit) : false
        }
    }

    struct DividerDouble: View {
        var body: some View {
            VStack(spacing: 2) {
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(.gray.opacity(0.65))
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(.gray.opacity(0.65))
            }
            .frame(height: 4)
            .padding(.vertical)
        }
    }

    struct DividerCustom: View {
        var body: some View {
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.gray.opacity(0.65))
                .padding(.vertical)
        }
    }
}
