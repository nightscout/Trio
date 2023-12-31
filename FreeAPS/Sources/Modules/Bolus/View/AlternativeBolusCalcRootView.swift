import Charts
import CoreData
import SwiftUI
import Swinject

extension Bolus {
    struct AlternativeBolusCalcRootView: BaseView {
        let resolver: Resolver
        let waitForSuggestion: Bool
        let fetch: Bool
        @StateObject var state: StateModel
        @State private var showInfo = false
        @State private var exceededMaxBolus = false
        @State private var keepForNextWiew: Bool = false
        @State private var calculatorDetent = PresentationDetent.medium

        private enum Config {
            static let dividerHeight: CGFloat = 2
            static let spacing: CGFloat = 3
        }

        @Environment(\.colorScheme) var colorScheme

        @FetchRequest(
            entity: Meals.entity(),
            sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: false)]
        ) var meal: FetchedResults<Meals>

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

        var body: some View {
            Form {
                Section {
                    if state.waitForSuggestion {
                        Text("Please wait")
                    } else {
                        predictionChart
                    }
                } header: { Text("Predictions") }

                Section {}
                if fetch {
                    Section {
                        mealEntries
                    } header: { Text("Meal Summary") }
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

                    if state.waitForSuggestion {
                        HStack {
                            Text("Wait please").foregroundColor(.secondary)
                            Spacer()
                            ActivityIndicator(isAnimating: .constant(true), style: .medium) // fix iOS 15 bug
                        }
                    } else {
                        HStack {
                            Text("Recommended Bolus")
                            Spacer()
                            Text(
                                formatter
                                    .string(from: Double(state.insulinCalculated) as NSNumber) ?? ""
                            )
                            Text(
                                NSLocalizedString(" U", comment: "Unit in number of units delivered (keep the space character!)")
                            ).foregroundColor(.secondary)
                        }.contentShape(Rectangle())
                            .onTapGesture { state.amount = state.insulinCalculated }
                    }

                    HStack {
                        Text("Bolus")
                        Spacer()
                        DecimalTextField(
                            "0",
                            value: $state.amount,
                            formatter: formatter,
                            autofocus: false,
                            cleanInput: true
                        )
                        Text(exceededMaxBolus ? "😵" : " U").foregroundColor(.secondary)
                    }
                    .onChange(of: state.amount) { newValue in
                        if newValue > state.maxBolus {
                            exceededMaxBolus = true
                        } else {
                            exceededMaxBolus = false
                        }
                    }

                } header: { Text("Bolus") }

                if state.amount > 0 {
                    Section {
                        Button {
                            keepForNextWiew = true
                            state.add()
                        }
                        label: { Text(exceededMaxBolus ? "Max Bolus exceeded!" : "Enact bolus") }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .disabled(disabled)
                            .listRowBackground(!disabled ? Color(.systemBlue) : Color(.systemGray4))
                            .tint(.white)
                    }
                }
                if state.amount <= 0 {
                    Section {
                        Button {
                            keepForNextWiew = true
                            state.showModal(for: nil)
                        }
                        label: { Text("Continue without bolus") }.frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }.scrollContentBackground(.hidden).background(color)
            .blur(radius: showInfo ? 3 : 0)
            .navigationTitle("Enact Bolus")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button {
                    carbsView()
                }
                label: {
                    HStack {
                        Image(systemName: "chevron.backward")
                        Text("Meal")
                    }
                },
                trailing: Button { state.hideModal() }
                label: { Text("Close") }
            )
            .onAppear {
                configureView {
                    state.waitForSuggestionInitial = waitForSuggestion
                    state.waitForSuggestion = waitForSuggestion
                    state.insulinCalculated = state.calculateInsulin()
                }
            }
            .onDisappear {
                if fetch, hasFatOrProtein, !keepForNextWiew, state.useCalc {
                    state.delete(deleteTwice: true, meal: meal)
                } else if fetch, !keepForNextWiew, state.useCalc {
                    state.delete(deleteTwice: false, meal: meal)
                }
            }
            .sheet(isPresented: $showInfo) {
                calculationsDetailView
                    .presentationDetents(
                        [fetch ? .large : .fraction(0.9), .large],
                        selection: $calculatorDetent
                    )
            }
        }

        private var color: LinearGradient {
            colorScheme == .dark ?  LinearGradient(
                gradient: Gradient(colors: [
                    // RGB(10, 34, 55)
                    Color(red: 0.03921568627, green: 0.1333333333, blue: 0.2156862745),
                    // RGB(3, 15, 28)
                    Color(red: 0.011, green: 0.058, blue: 0.109),
                    // RGB(10, 34, 55)
                    Color(red: 0.03921568627, green: 0.1333333333, blue: 0.2156862745)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
                :
                LinearGradient(gradient: Gradient(colors: [Color.gray.opacity(0.1)]), startPoint: .top, endPoint: .bottom)
        }

        var predictionChart: some View {
            ZStack {
                PredictionView(
                    predictions: $state.predictions, units: $state.units, eventualBG: $state.evBG, target: $state.target,
                    displayPredictions: $state.displayPredictions
                )
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

                let firstRow = currentBG
                    .formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits)))

                    + " - " +
                    target
                    .formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits)))
                    + " = " +
                    state.targetDifference
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

                let secondRow = state.targetDifference
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
                    Text((state.iob != 0 ? "-" : "") + (state.iob >= 0 ? iobFormatted : "(" + iobFormatted + ")"))
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
                        state.cob
                            .formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits))) +
                            NSLocalizedString(" g", comment: "grams")
                    )
                }

                Text(
                    state.cob
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
                        .foregroundColor(.blue)
                    Text("U").foregroundColor(.secondary)
                }
                .gridColumnAlignment(.trailing)
                .fontWeight(.bold)
            }
        }

        var calcResultFormulaRow: some View {
            GridRow(alignment: .bottom) {
                if state.useFattyMealCorrectionFactor {
                    Text("Factor x Fatty Meal Factor x Full Bolus")
                        .foregroundColor(.secondary.opacity(colorScheme == .dark ? 0.65 : 0.8))
                        .font(.caption)
                        .gridCellAnchor(.center)
                        .gridCellColumns(3)
                } else if state.useSuperBolus {
                    Text("(Factor x Full Bolus) + Super Bolus")
                        .foregroundColor(.secondary.opacity(colorScheme == .dark ? 0.65 : 0.8))
                        .font(.caption)
                        .gridCellAnchor(.center)
                        .gridCellColumns(3)
                } else {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    Text("Factor x Full Bolus")
                        .foregroundColor(.secondary.opacity(colorScheme == .dark ? 0.65 : 0.8))
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

                        if fetch {
                            // meal entries as grid rows

                            GridRow {
                                if let carbs = meal.first?.carbs, carbs > 0 {
                                    Text("Carbs").foregroundColor(.secondary)
                                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                                    HStack {
                                        Text(carbs.formatted())
                                        Text("g").foregroundColor(.secondary)
                                    }.gridCellAnchor(.trailing)
                                }
                            }

                            GridRow {
                                if let fat = meal.first?.fat, fat > 0 {
                                    Text("Fat").foregroundColor(.secondary)
                                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                                    HStack {
                                        Text(fat.formatted())
                                        Text("g").foregroundColor(.secondary)
                                    }.gridCellAnchor(.trailing)
                                }
                            }

                            GridRow {
                                if let protein = meal.first?.protein, protein > 0 {
                                    Text("Protein").foregroundColor(.secondary)
                                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                                    HStack {
                                        Text(protein.formatted())
                                        Text("g").foregroundColor(.secondary)
                                    }.gridCellAnchor(.trailing)
                                }
                            }

                            GridRow {
                                if let note = meal.first?.note, note != "" {
                                    Text("Note").foregroundColor(.secondary)
                                    Text(note).foregroundColor(.secondary).gridCellColumns(2).gridCellAnchor(.trailing)
                                }
                            }

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
                .font(.system(size: 15))
            }
        }

        private func insulinRounder(_ value: Decimal) -> Decimal {
            let toRound = NSDecimalNumber(decimal: value).doubleValue
            return Decimal(floor(100 * toRound) / 100)
        }

        private var disabled: Bool {
            state.amount <= 0 || state.amount > state.maxBolus
        }

        var changed: Bool {
            ((meal.first?.carbs ?? 0) > 0) || ((meal.first?.fat ?? 0) > 0) || ((meal.first?.protein ?? 0) > 0)
        }

        var hasFatOrProtein: Bool {
            ((meal.first?.fat ?? 0) > 0) || ((meal.first?.protein ?? 0) > 0)
        }

        func carbsView() {
            if fetch {
                keepForNextWiew = true
                state.backToCarbsView(complexEntry: true, meal, override: false)
            } else {
                state.backToCarbsView(complexEntry: false, meal, override: true)
            }
        }

        var mealEntries: some View {
            VStack {
                if let carbs = meal.first?.carbs, carbs > 0 {
                    HStack {
                        Text("Carbs").foregroundColor(.secondary)
                        Spacer()
                        Text(carbs.formatted())
                        Text("g").foregroundColor(.secondary)
                    }
                }
                if let fat = meal.first?.fat, fat > 0 {
                    HStack {
                        Text("Fat").foregroundColor(.secondary)
                        Spacer()
                        Text(fat.formatted())
                        Text("g").foregroundColor(.secondary)
                    }
                }
                if let protein = meal.first?.protein, protein > 0 {
                    HStack {
                        Text("Protein").foregroundColor(.secondary)
                        Spacer()
                        Text(protein.formatted())
                        Text("g").foregroundColor(.secondary)
                    }
                }
                if let note = meal.first?.note, note != "" {
                    HStack {
                        Text("Note").foregroundColor(.secondary)
                        Spacer()
                        Text(note).foregroundColor(.secondary)
                    }
                }
            }
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
