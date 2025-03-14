import SwiftUI

// MARK: - Style Extensions

extension View {
    /// Applies secondary label styling
    func secondaryLabel() -> some View {
        font(.subheadline)
            .foregroundStyle(.secondary)
            .minimumScaleFactor(0.5)
    }

    /// Applies tertiary label styling
    func tertiaryLabel() -> some View {
        font(.caption)
            .foregroundStyle(.tertiary)
            .minimumScaleFactor(0.5)
    }

    /// Applies value styling
    func valueStyle() -> some View {
        font(.system(.title2, design: .rounded, weight: .semibold))
            .minimumScaleFactor(0.5)
    }

    /// Applies large value styling
    func largeValueStyle() -> some View {
        font(.system(.largeTitle, design: .rounded, weight: .bold))
            .minimumScaleFactor(0.5)
    }

    /// Applies section title styling
    func sectionTitle() -> some View {
        font(.headline)
            .foregroundStyle(.secondary)
            .minimumScaleFactor(0.5)
    }

    /// Applies unit text styling
    func unitStyle() -> some View {
        font(.subheadline)
            .foregroundStyle(.secondary)
            .minimumScaleFactor(0.5)
    }

    /// Applies to mathematical operators
    func operatorStyle() -> some View {
        font(.system(size: 24, weight: .regular))
            .foregroundStyle(.secondary)
    }

    /// Applies leading alignment with full width
    func leadingFullWidth() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Applies trailing alignment with full width
    func trailingFullWidth() -> some View {
        frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// Applies center alignment with full width
    func centerFullWidth() -> some View {
        frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Card Modifier

struct CalculationCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))

            content
                .padding(16)
        }
        .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
    }
}

extension View {
    func calculationCardStyle() -> some View {
        modifier(CalculationCardModifier())
    }
}

// MARK: - ValueItem for Factors Card

// Define a structure to represent a value item with optional formatting
struct ValueItem {
    let text: String
    var isOperator: Bool = false
    var isParenthesis: Bool = false
    var color: Color? = nil
}

// MARK: - Main Code Example

struct PopupView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss

    var state: Treatments.StateModel

    @State var calcPopupDetent = PresentationDetent.large

    private var fractionDigits: Int {
        if state.units == .mmolL {
            return 1
        } else { return 0 }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading) {
                Text(
                    "The bolus calculator uses various inputs to determine the recommended insulin dosage. Find the detailed calculations below."
                )
                .secondaryLabel()

                ScrollView {
                    VStack(spacing: 24) {
                        // Calculation Cards
                        calculationCards

                        // Result Section
                        resultSection

                        Spacer()
                    }
                }

                Button {
                    state.showInfo = false
                } label: {
                    Text("Got it!").bold().centerFullWidth().frame(minHeight: 30)
                }
                .buttonStyle(.bordered)
                .padding(.top)
            }
            .padding([.horizontal, .bottom])
            .navigationBarTitle("Detailed Bolus Calculations", displayMode: .inline)
            .presentationDetents(
                [.fraction(0.9), .large],
                selection: $calcPopupDetent
            )
        }
    }

    // MARK: - Calculation Cards

    var calculationCards: some View {
        VStack(spacing: 16) {
            glucoseCard
            iobCard
            cobCard
            deltaCard
            fullBolusCard

            if state.useSuperBolus {
                superBolusCard
            }

            if state.factoredInsulin > 0 {
                factorsCard
            }
        }
    }

    // MARK: - Individual Cards

    var glucoseCard: some View {
        calculationCardView("Glucose Calculation") {
            Grid {
                // Row 1: Titles
                GridRow {
                    Text("") // Placeholder for left bracket
                    Text("Current").secondaryLabel()
                    Text("") // Placeholder for minus sign
                    Text("Target").secondaryLabel()
                    Text("") // Placeholder for right bracket and division
                    Text("ISF").secondaryLabel()
                    Text("") // Placeholder for equals sign
                    Text("Addend").secondaryLabel()
                }

                // Row 2: Values
                GridRow {
                    Text("(")
                        .font(.system(.title, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(state.units == .mmolL ? state.currentBG.formattedAsMmolL : state.currentBG.description)
                        .valueStyle()
                    Text("−")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(state.units == .mmolL ? state.target.formattedAsMmolL : state.target.description)
                        .valueStyle()
                    Text(")/")
                        .font(.system(.title, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(state.units == .mmolL ? state.isf.formattedAsMmolL : state.isf.description)
                        .valueStyle()
                    Text("=").operatorStyle()
                    Text(insulinFormatter(state.targetDifferenceInsulin))
                        .valueStyle()
                        .foregroundStyle(addendColor(state.targetDifferenceInsulin) ?? .primary)
                }

                // Row 3: Units
                GridRow {
                    Text("") // Placeholder for left bracket
                    Text(state.units.rawValue).unitStyle()
                    Text("") // Placeholder for minus sign
                    Text(state.units.rawValue).unitStyle()
                    Text("") // Placeholder for right bracket and division
                    Text("\(state.units.rawValue)/U").unitStyle()
                    Text("") // Placeholder for equals sign
                    Text("U").unitStyle()
                }
            }
            .multilineTextAlignment(.center)
            .trailingFullWidth()
        }
    }

    var iobCard: some View {
        calculationCardView("Insulin On Board (IOB)") {
            Grid {
                // Row 1: Titles
                GridRow {
                    Text("Subtract").secondaryLabel()
                    Text("") // Placeholder for multiplication sign
                    Text("IOB").secondaryLabel()
                    Text("") // Placeholder for equals sign
                    Text("Addend").secondaryLabel()
                }

                // Row 2: Values
                GridRow {
                    Text("-1").valueStyle()
                    Text("×").operatorStyle()
                    Text(insulinFormatter(state.iob, .plain)).valueStyle()
                    Text("=").operatorStyle()
                    Text(insulinFormatter(-1 * state.iob, .plain))
                        .valueStyle()
                        .foregroundStyle(addendColor(-1 * state.iob) ?? .primary)
                }

                // Row 3: Units
                GridRow {
                    Text("") // Placeholder for subtract
                    Text("") // Placeholder for multiplication sign
                    Text("U").unitStyle()
                    Text("") // Placeholder for equals sign
                    Text("U").unitStyle()
                }
            }
            .multilineTextAlignment(.center)
            .trailingFullWidth()
        }
    }

    var cobCard: some View {
        calculationCardView("Carbs On Board (COB)") {
            let exceededMax: Bool = Decimal(state.cob) + state.carbs > state.maxCOB
            Grid {
                // Row 1: COB breakdown calculation title
                GridRow {
                    Text("") // Placeholder for opening bracket
                    Text("COB").secondaryLabel()
                    Text("") // Placeholder for plus sign
                    Text("Carbs").secondaryLabel()
                    Text("") // Placeholder for closing bracket
                    Text("") // Placeholder for division sign
                    Text("CR").secondaryLabel()
                    Text("") // Placeholder for equals sign
                    Text("").secondaryLabel() // Empty to match bottom row
                }

                // Row 2: COB breakdown values
                GridRow {
                    Text("(")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(
                        Decimal(state.cob)
                            .formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits)))
                    )
                    .valueStyle()
                    Text("+")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(
                        state.carbs
                            .formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits)))
                    )
                    .valueStyle()
                    Text(")")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("/")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(state.carbRatio.formatted()).valueStyle()
                    Text("=").operatorStyle()
                    Text(exceededMax ? "" : insulinFormatter(state.wholeCobInsulin))
                        .valueStyle()
                        .foregroundStyle(addendColor(state.wholeCobInsulin) ?? .primary)
                }

                // Row 3: Units
                GridRow {
                    Text("").unitStyle() // Empty for opening bracket
                    Text("g").unitStyle()
                    Text("").unitStyle() // Empty for plus sign
                    Text("g").unitStyle()
                    Text("").unitStyle() // Empty for closing bracket
                    Text("").unitStyle() // Empty for division sign
                    Text("g/U").unitStyle()
                    Text("").unitStyle() // Empty for equals sign
                    Text(exceededMax ? "" : "U").unitStyle()
                }

                if exceededMax {
                    Divider()
                        .padding(.vertical, 4)
                        .gridCellColumns(9)

                    // Row 4: Calculation titles
                    GridRow {
                        Text("") // Placeholder
                        Text("") // Placeholder
                        Text("") // Placeholder
                        Text(exceededMax ? "Max COB" : "New COB").secondaryLabel().gridCellColumns(2)
                        Text("") // Placeholder for division sign
                        Text("CR").secondaryLabel()
                        Text("") // Placeholder for equals sign
                        Text("Addend").secondaryLabel()
                    }

                    // Row 5: Values
                    GridRow {
                        Text("") // Placeholder
                        Text("") // Placeholder
                        Text("") // Placeholder
                        Text(
                            state.wholeCob
                                .formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits)))
                        )
                        .valueStyle()
                        .foregroundStyle(exceededMax ? .red : .primary)
                        .gridCellColumns(2)
                        Text("/")
                            .font(.system(.title2, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(state.carbRatio.formatted()).valueStyle()
                        Text("=").operatorStyle()
                        Text(insulinFormatter(state.wholeCobInsulin))
                            .valueStyle()
                            .foregroundStyle(addendColor(state.wholeCobInsulin) ?? .primary)
                    }

                    // Row 6: Units
                    GridRow {
                        Text("") // Placeholder
                        Text("") // Placeholder
                        Text("") // Placeholder
                        Text("g").unitStyle().gridCellColumns(2)
                        Text("") // Placeholder for division sign
                        Text("g/U").unitStyle()
                        Text("") // Placeholder for equals sign
                        Text("U").unitStyle()
                    }
                }
            }
            .multilineTextAlignment(.center)
            .trailingFullWidth()
        }
    }

    var deltaCard: some View {
        calculationCardView("Glucose Trend (15 min)") {
            Grid {
                // Row 1: Titles
                GridRow {
                    Text("Delta").secondaryLabel()
                    Text("") // Placeholder for division sign
                    Text("ISF").secondaryLabel()
                    Text("") // Placeholder for equals sign
                    Text("Addend").secondaryLabel()
                }

                // Row 2: Values
                GridRow {
                    Text(state.units == .mmolL ? state.deltaBG.formattedAsMmolL : state.deltaBG.description)
                        .valueStyle()
                    Text("/")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(state.units == .mmolL ? state.isf.formattedAsMmolL : state.isf.description)
                        .valueStyle()
                    Text("=").operatorStyle()
                    Text(insulinFormatter(state.fifteenMinInsulin))
                        .valueStyle()
                        .foregroundStyle(addendColor(state.fifteenMinInsulin) ?? .primary)
                }

                // Row 3: Units
                GridRow {
                    Text(state.units.rawValue).unitStyle()
                    Text("") // Placeholder for division sign
                    Text("\(state.units.rawValue)/U").unitStyle()
                    Text("") // Placeholder for equals sign
                    Text("U").unitStyle()
                }
            }
            .multilineTextAlignment(.center)
            .trailingFullWidth()
        }
    }

    var fullBolusCard: some View {
        calculationCardView("Full Bolus") {
            Grid {
                // Total value row
                GridRow {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(insulinFormatter(state.wholeCalc))
                            .largeValueStyle()
                            .foregroundStyle(addendColor(state.wholeCalc) ?? .green)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("U")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .gridCellColumns(7)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity) // Use full width
                }

                // Divider row
                GridRow {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 1)
                        .gridCellColumns(7)
                }

                // Row 1: Titles
                GridRow {
                    Text("Glucose").secondaryLabel()
                    Text("") // Placeholder for first plus sign
                    Text("IOB").secondaryLabel()
                    Text("") // Placeholder for second plus sign
                    Text("COB").secondaryLabel()
                    Text("") // Placeholder for third plus sign
                    Text("Delta").secondaryLabel()
                }

                // Row 2: Values
                GridRow {
                    Text(insulinFormatter(state.targetDifferenceInsulin))
                        .valueStyle()
                        .foregroundStyle(addendColor(state.targetDifferenceInsulin) ?? .primary)
                    Text("+")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(insulinFormatter(-1 * state.iob, .plain))
                        .valueStyle()
                        .foregroundStyle(addendColor(-1 * state.iob) ?? .primary)
                    Text("+")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(insulinFormatter(state.wholeCobInsulin))
                        .valueStyle()
                        .foregroundStyle(addendColor(state.wholeCobInsulin) ?? .primary)
                    Text("+")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(insulinFormatter(state.fifteenMinInsulin))
                        .valueStyle()
                        .foregroundStyle(addendColor(state.fifteenMinInsulin) ?? .primary)
                }

                // Row 3: Units
                GridRow {
                    Text("U").unitStyle()
                    Text("") // Placeholder for first plus sign
                    Text("U").unitStyle()
                    Text("") // Placeholder for second plus sign
                    Text("U").unitStyle()
                    Text("") // Placeholder for third plus sign
                    Text("U").unitStyle()
                }
            }
            .multilineTextAlignment(.center)
        }
    }

    var superBolusCard: some View {
        calculationCardView("Super Bolus") {
            Grid {
                // Row 1: Titles
                GridRow {
                    Text("Basal Rate").secondaryLabel()
                    Text("") // Placeholder for multiplication sign
                    Text("Super Bolus %").secondaryLabel()
                    Text("") // Placeholder for equals sign
                    Text("Addend").secondaryLabel()
                }

                // Row 2: Values
                GridRow {
                    Text("\(state.currentBasal)").valueStyle()
                    Text("×")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text((100 * state.sweetMealFactor).formatted()).valueStyle()
                    Text("=").operatorStyle()
                    Text(insulinFormatter(state.superBolusInsulin))
                        .valueStyle()
                        .foregroundStyle(addendColor(state.superBolusInsulin) ?? .primary)
                }

                // Row 3: Units
                GridRow {
                    Text("U/hr").unitStyle()
                    Text("") // Placeholder for multiplication sign
                    Text("%").unitStyle()
                    Text("") // Placeholder for equals sign
                    Text("U").unitStyle()
                }
            }
            .multilineTextAlignment(.center)
            .trailingFullWidth()
        }
    }

    // MARK: - Refactored Factors Card

    var factorsCard: some View {
        calculationCardView("Applied Factors") {
            Grid {
                // Choose the layout based on which factors are active
                switch (state.useSuperBolus, state.useFattyMealCorrectionFactor) {
                case (false, false):
                    // Simple case: just Full Bolus × Rec. Bolus %
                    factorRowTitles(["Full Bolus", "", "Rec. Bolus %", "", "Result"])
                    factorRowValues([
                        ValueItem(text: insulinFormatter(state.wholeCalc)),
                        ValueItem(text: "×", isOperator: true),
                        ValueItem(text: (100 * state.fraction).formatted()),
                        ValueItem(text: "=", isOperator: true),
                        ValueItem(text: insulinFormatter(state.factoredInsulin), color: addendColor(state.factoredInsulin))
                    ])
                    factorRowUnits(["U", "", "%", "", "U"])

                case (false, true):
                    // Case: Full Bolus × Rec. Bolus % × Fatty Meal %
                    factorRowTitles(["Full Bolus", "", "Rec. %", "", "Fatty %", "", "Result"])
                    factorRowValues([
                        ValueItem(text: insulinFormatter(state.wholeCalc)),
                        ValueItem(text: "×", isOperator: true),
                        ValueItem(text: (100 * state.fraction).formatted()),
                        ValueItem(text: "×", isOperator: true),
                        ValueItem(text: (100 * state.fattyMealFactor).formatted()),
                        ValueItem(text: "=", isOperator: true),
                        ValueItem(text: insulinFormatter(state.factoredInsulin), color: addendColor(state.factoredInsulin))
                    ])
                    factorRowUnits(["U", "", "%", "", "%", "", "U"])

                case (true, false):
                    // Case: (Full Bolus × Rec. Bolus %) + Super Bolus
                    factorRowTitles(["", "Full Bolus", "", "Rec. %", "", "", "Super Bolus", "", "Result"])
                    factorRowValues([
                        ValueItem(text: "(", isParenthesis: true),
                        ValueItem(text: insulinFormatter(state.wholeCalc)),
                        ValueItem(text: "×", isOperator: true),
                        ValueItem(text: (100 * state.fraction).formatted()),
                        ValueItem(text: ")", isParenthesis: true),
                        ValueItem(text: "+", isOperator: true),
                        ValueItem(text: insulinFormatter(state.superBolusInsulin)),
                        ValueItem(text: "=", isOperator: true),
                        ValueItem(text: insulinFormatter(state.factoredInsulin), color: addendColor(state.factoredInsulin))
                    ])
                    factorRowUnits(["", "U", "", "%", "", "", "U", "", "U"])

                case (true, true):
                    // Most complex case: (Full Bolus × Rec. Bolus % × Fatty Meal %) + Super Bolus
                    // Header
                    GridRow {
                        Text(factorsFormulaText())
                            .tertiaryLabel()
                            .gridCellColumns(5)
                    }

                    // Divider
                    GridRow {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 1)
                            .gridCellColumns(5)
                    }

                    // Titles, values and units
                    factorRowTitles(["Full Calculation", "", "Factors", "", "Result"])

                    GridRow {
                        Text(insulinFormatter(state.wholeCalc)).valueStyle()
                        Text("×")
                            .font(.system(.title2, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .center) {
                            Text("\((100 * state.fraction).formatted())% × \((100 * state.fattyMealFactor).formatted())%")
                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                            Text("+ \(insulinFormatter(state.superBolusInsulin)) U")
                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                        }
                        Text("=").operatorStyle()
                        Text(insulinFormatter(state.factoredInsulin))
                            .valueStyle()
                            .foregroundStyle(addendColor(state.factoredInsulin) ?? .primary)
                    }

                    factorRowUnits(["U", "", "", "", "U"])
                }
            }
            .multilineTextAlignment(.center)
            .trailingFullWidth()
        }
    }

    // Helper functions for factorsCard
    func factorRowTitles(_ titles: [String]) -> some View {
        GridRow {
            ForEach(titles.indices, id: \.self) { index in
                Text(titles[index]).secondaryLabel()
            }
        }
    }

    func factorRowValues(_ items: [ValueItem]) -> some View {
        GridRow {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]

                if item.isOperator {
                    Text(item.text)
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                } else if item.isParenthesis {
                    Text(item.text)
                        .font(.system(.title, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Text(item.text)
                        .valueStyle()
                        .foregroundStyle(item.color ?? .primary)
                }
            }
        }
    }

    func factorRowUnits(_ units: [String]) -> some View {
        GridRow {
            ForEach(units.indices, id: \.self) { index in
                Text(units[index]).unitStyle()
            }
        }
    }

    // MARK: - Result Section

    var resultSection: some View {
        VStack(spacing: 8) {
            Text("Recommended Bolus")
                .font(.title2)
                .fontWeight(.bold)
                .minimumScaleFactor(0.5)
                .padding(.vertical, 8)

            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.accentColor.opacity(0.1))

                VStack(spacing: 16) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(insulinFormatter(state.insulinCalculated))
                            .largeValueStyle()
                            .foregroundStyle(state.insulinCalculated > 0 ? Color.accentColor : .primary)

                        Text("U")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .minimumScaleFactor(0.5)
                    }

                    Divider()

                    if state.factoredInsulin > state.insulinCalculated && state.insulinCalculated > 0 {
                        Text("Limited from \(insulinFormatter(state.factoredInsulin)) U")
                            .secondaryLabel()
                    }

                    limitDetailsView()
                }
                .padding()
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Helper Views

    func calculationCardView<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).sectionTitle()
            content().calculationCardStyle()
        }
    }

    func valueLabelView(title: String, value: String, unit: String? = nil, valueColor: Color? = nil) -> some View {
        Grid(alignment: .center, verticalSpacing: 4) {
            GridRow {
                Text(title).secondaryLabel()
            }

            GridRow {
                Text(value)
                    .valueStyle()
                    .foregroundStyle(valueColor ?? .primary)
            }

            if let unit = unit {
                GridRow {
                    Text(unit).unitStyle()
                }
            }
        }.multilineTextAlignment(.center)
    }

    func limitDetailsView() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            let iobAvailable: Decimal = state.maxIOB - state.iob
            let isLoopStale = state.lastLoopDate == nil ||
                Date().timeIntervalSince(state.lastLoopDate!) > 15 * 60

            if isLoopStale {
                limitWarning("Last loop was > 15 mins ago.")
            } else if state.factoredInsulin < 0 {
                limitWarning("No insulin recommended.")
            } else if state.currentBG < 54 {
                limitWarning("Glucose is very low.")
            } else if state.minPredBG < 54 {
                limitWarning("Glucose forecast is very low.")
            } else if state.maxBolus <= iobAvailable, state.factoredInsulin > state.maxBolus {
                limitWarning("Max Bolus = \(insulinFormatter(state.maxBolus)) U")
            } else {
                if state.factoredInsulin > iobAvailable {
                    Grid(alignment: .leading, verticalSpacing: 4) {
                        GridRow {
                            Text("Available IOB:")
                                .secondaryLabel()

                            Text("\(insulinFormatter(iobAvailable)) U")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.accentColor)
                                .minimumScaleFactor(0.5)
                                .leadingFullWidth()
                        }

                        GridRow {
                            let iobFormatted = state.iob < 0 ? "(\(insulinFormatter(state.iob)))" : insulinFormatter(state.iob)
                            Text("\(insulinFormatter(state.maxIOB)) - \(iobFormatted)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .minimumScaleFactor(0.5)
                                .leadingFullWidth()
                                .gridCellColumns(2)
                        }

                        GridRow {
                            Text("Max IOB - Current IOB")
                                .tertiaryLabel()
                                .leadingFullWidth()
                                .gridCellColumns(2)
                        }
                    }
                }

                if state.insulinCalculated > 0 {
                    Text("Rounded for pump")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .minimumScaleFactor(0.5)
                        .padding(.top, 4)
                        .trailingFullWidth()
                }
            }
        }
    }

    func limitWarning(_ text: String) -> some View {
        Grid {
            GridRow {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)

                Text(text)
                    .fontWeight(.medium)
                    .foregroundStyle(.red)
                    .minimumScaleFactor(0.5)
                    .leadingFullWidth()
            }
        }
        .font(.subheadline)
    }

    // MARK: - Helper Methods

    func factorsCalculationText() -> String {
        var text = ""

        if state.useSuperBolus {
            text += "(\(insulinFormatter(state.wholeCalc)) × \((100 * state.fraction).formatted())%)"

            if state.useFattyMealCorrectionFactor {
                text += " × \((100 * state.fattyMealFactor).formatted())%"
            }

            text += " + \(insulinFormatter(state.superBolusInsulin))"
        } else {
            text += "\(insulinFormatter(state.wholeCalc)) × \((100 * state.fraction).formatted())%"

            if state.useFattyMealCorrectionFactor {
                text += " × \((100 * state.fattyMealFactor).formatted())%"
            }
        }

        return text
    }

    func factorsFormulaText() -> String {
        if state.useFattyMealCorrectionFactor && state.useSuperBolus {
            return "(Full Bolus × Rec. Bolus % × Fatty Meal %) + Super Bolus"
        } else if state.useFattyMealCorrectionFactor {
            return "Full Bolus × Rec. Bolus % × Fatty Meal %"
        } else if state.useSuperBolus {
            return "(Full Bolus × Rec. Bolus %) + Super Bolus"
        } else {
            return "Full Bolus × Rec. Bolus %"
        }
    }

    func insulinFormatter(_ value: Decimal, _ roundingMode: NSDecimalNumber.RoundingMode = .down) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.locale = Locale.current

        let handler = NSDecimalNumberHandler(
            roundingMode: roundingMode,
            scale: 2,
            raiseOnExactness: false,
            raiseOnOverflow: false,
            raiseOnUnderflow: false,
            raiseOnDivideByZero: false
        )

        let roundedValue = NSDecimalNumber(decimal: value).rounding(accordingToBehavior: handler)

        return formatter.string(from: roundedValue) ?? "\(value)"
    }

    func addendColor(_ value: Decimal) -> Color? {
        switch value {
        case ..<0:
            return .red
        case 0:
            return nil
        default:
            return .green
        }
    }
}
