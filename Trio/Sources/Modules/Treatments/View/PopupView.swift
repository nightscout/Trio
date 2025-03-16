import SwiftUI

// MARK: - Style Extensions

private extension View {
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

    /// Applies unit text styling
    func percentStyle() -> some View {
        font(.subheadline)
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

private struct CalculationCardModifier: ViewModifier {
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

private extension View {
    func calculationCardStyle() -> some View {
        modifier(CalculationCardModifier())
    }
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
                ScrollView {
                    VStack(spacing: 24) {
                        Text(
                            "The bolus calculator uses various inputs to determine the recommended insulin dosage. Find the detailed calculations below."
                        )
                        .secondaryLabel()

                        calculationCards
                    }
                }

                recommendedBolusCard

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
                GridRow(alignment: .bottom) {
                    Text("") // Placeholder for left bracket
                    Text("Current").secondaryLabel()
                    Text("") // Placeholder for minus sign
                    Text("Target").secondaryLabel()
                    Text("") // Placeholder for right bracket and division
                    Text("ISF").secondaryLabel()
                    Spacer(minLength: 0)
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
                    Spacer(minLength: 0)
                    Text("=").operatorStyle()
                    Text(insulinFormatter(state.targetDifferenceInsulin))
                        .valueStyle()
                        .foregroundStyle(addendColor(state.targetDifferenceInsulin) ?? .primary)
                }

                // Row 3: Units
                GridRow(alignment: .top) {
                    Text("") // Placeholder for left bracket
                    Text(state.units.rawValue).unitStyle()
                    Text("") // Placeholder for minus sign
                    Text(state.units.rawValue).unitStyle()
                    Text("") // Placeholder for right bracket and division
                    Text("\(state.units.rawValue)/U").unitStyle()
                    Spacer(minLength: 0)
                    Text("") // Placeholder for equals sign
                    Text("U").unitStyle()
                }
            }
            .multilineTextAlignment(.center)
            .leadingFullWidth()
        }
    }

    var iobCard: some View {
        calculationCardView("Insulin On Board (IOB)") {
            Grid {
                // Row 1: Titles
                GridRow(alignment: .bottom) {
                    Text("Subtract").secondaryLabel()
                    Text("") // Placeholder for multiplication sign
                    Text("IOB").secondaryLabel()
                    Spacer(minLength: 0)
                    Text("") // Placeholder for equals sign
                    Text("Addend").secondaryLabel()
                }

                // Row 2: Values
                GridRow {
                    Text("-1").valueStyle()
                    Text("×").operatorStyle()
                    Text(insulinFormatter(state.iob, .plain)).valueStyle()
                    Spacer(minLength: 0)
                    Text("=").operatorStyle()
                    Text(insulinFormatter(-1 * state.iob, .plain))
                        .valueStyle()
                        .foregroundStyle(addendColor(-1 * state.iob) ?? .primary)
                }

                // Row 3: Units
                GridRow(alignment: .top) {
                    Text("") // Placeholder for subtract
                    Text("") // Placeholder for multiplication sign
                    Text("U").unitStyle()
                    Spacer(minLength: 0)
                    Text("") // Placeholder for equals sign
                    Text("U").unitStyle()
                }
            }
            .multilineTextAlignment(.center)
            .leadingFullWidth()
        }
    }

    var cobCard: some View {
        calculationCardView("Carbs On Board (COB)") {
            let exceededMaxCOB: Bool = Decimal(state.cob) + state.carbs > state.maxCOB
            Grid {
                // Row 1: COB breakdown calculation title
                GridRow(alignment: .bottom) {
                    Text("") // Placeholder for opening bracket
                    Text("COB").secondaryLabel()
                    Text("") // Placeholder for plus sign
                    Text("Carbs").secondaryLabel()
                    Text("") // Placeholder for closing bracket
                    Text("") // Placeholder for division sign
                    Text("CR").secondaryLabel()
                    Spacer()
                    Text("") // Placeholder for equals sign
                    Text(exceededMaxCOB ? "" : "Addend").secondaryLabel()
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
                    Spacer()
                    Text("=").operatorStyle()
                    Text(exceededMaxCOB ? "" : insulinFormatter(state.wholeCobInsulin))
                        .valueStyle()
                        .foregroundStyle(addendColor(state.wholeCobInsulin) ?? .primary)
                }

                // Row 3: Units
                GridRow(alignment: .top) {
                    Text("").unitStyle() // Empty for opening bracket
                    Text("g").unitStyle()
                    Text("").unitStyle() // Empty for plus sign
                    Text("g").unitStyle()
                    Text("").unitStyle() // Empty for closing bracket
                    Text("").unitStyle() // Empty for division sign
                    Text("g/U").unitStyle()
                    Spacer()
                    Text("").unitStyle() // Empty for equals sign
                    Text(exceededMaxCOB ? "" : "U").unitStyle()
                }

                //
                if exceededMaxCOB {
                    Divider()
                        .padding(.vertical, 4)
                        .gridCellColumns(9)

                    // Row 4: Calculation titles
                    GridRow(alignment: .bottom) {
                        Text("") // Placeholder for open bracket
                        Text("Max COB").secondaryLabel().gridCellColumns(3)
                        Text("") // Placeholder for closed bracket
                        Text("") // Placeholder for division sign
                        Text("CR").secondaryLabel()
                        Spacer(minLength: 0)
                        Text("") // Placeholder for equals sign
                        Text("Addend").secondaryLabel()
                    }

                    // Row 5: Values
                    GridRow {
                        Text("(").operatorStyle()
                        Text(
                            state.wholeCob
                                .formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits)))
                        )
                        .valueStyle()
                        .foregroundStyle(.red)
                        .gridCellColumns(3)
                        Text(")").operatorStyle()
                        Text("/")
                            .font(.system(.title2, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(state.carbRatio.formatted()).valueStyle()
                        Spacer(minLength: 0)
                        Text("=").operatorStyle()
                        Text(insulinFormatter(state.wholeCobInsulin))
                            .valueStyle()
                            .foregroundStyle(addendColor(state.wholeCobInsulin) ?? .primary)
                    }

                    // Row 6: Units
                    GridRow(alignment: .top) {
                        Text("") // Placeholder for open bracket
                        Text("g").unitStyle().gridCellColumns(3)
                        Text("") // Placeholder for closed bracket
                        Text("") // Placeholder for division sign
                        Text("g/U").unitStyle()
                        Spacer(minLength: 0)
                        Text("") // Placeholder for equals sign
                        Text("U").unitStyle()
                    }
                }
            }
            .multilineTextAlignment(.center)
            .leadingFullWidth()
        }
    }

    var deltaCard: some View {
        calculationCardView("Glucose Trend (15 min)") {
            Grid {
                // Row 1: Titles
                GridRow(alignment: .bottom) {
                    Text("Delta").secondaryLabel()
                    Text("") // Placeholder for division sign
                    Text("ISF").secondaryLabel()
                    Spacer(minLength: 0)
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
                    Spacer(minLength: 0)
                    Text("=").operatorStyle()
                    Text(insulinFormatter(state.fifteenMinInsulin))
                        .valueStyle()
                        .foregroundStyle(addendColor(state.fifteenMinInsulin) ?? .primary)
                }

                // Row 3: Units
                GridRow(alignment: .top) {
                    Text(state.units.rawValue).unitStyle()
                    Text("") // Placeholder for division sign
                    Text("\(state.units.rawValue)/U").unitStyle()
                    Spacer(minLength: 0)
                    Text("") // Placeholder for equals sign
                    Text("U").unitStyle()
                }
            }
            .multilineTextAlignment(.center)
            .leadingFullWidth()
        }
    }

    var fullBolusCard: some View {
        calculationCardView("Full Bolus") {
            Grid {
                // Row 1: Titles
                GridRow(alignment: .bottom) {
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
                GridRow(alignment: .top) {
                    Text("U").unitStyle()
                    Text("") // Placeholder for first plus sign
                    Text("U").unitStyle()
                    Text("") // Placeholder for second plus sign
                    Text("U").unitStyle()
                    Text("") // Placeholder for third plus sign
                    Text("U").unitStyle()
                }

                // Divider row
                GridRow {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 1)
                        .gridCellColumns(7)
                }

                // Total value row
                GridRow {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("=")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .minimumScaleFactor(0.5)

                        Text(insulinFormatter(state.wholeCalc))
                            .largeValueStyle()
                            .foregroundStyle(addendColor(state.wholeCalc) ?? .secondary)

                        Text("U")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .minimumScaleFactor(0.5)
                    }
                    .gridCellColumns(7)
                    .gridCellAnchor(.trailing)
                }
                .trailingFullWidth()
            }
            .multilineTextAlignment(.center)
        }
    }

    var superBolusCard: some View {
        calculationCardView("Super Bolus") {
            Grid {
                // Row 1: Titles
                GridRow(alignment: .bottom) {
                    Text("Basal Rate").secondaryLabel()
                    Text("") // Placeholder for multiplication sign
                    Text("Super Bolus %").secondaryLabel()
                    Spacer(minLength: 0)
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
                    Spacer(minLength: 0)
                    Text("=").operatorStyle()
                    Text(insulinFormatter(state.superBolusInsulin))
                        .valueStyle()
                        .foregroundStyle(addendColor(state.superBolusInsulin) ?? .primary)
                }

                // Row 3: Units
                GridRow(alignment: .top) {
                    Text("U/hr").unitStyle()
                    Text("") // Placeholder for multiplication sign
                    Text("/100").percentStyle()
                    Spacer(minLength: 0)
                    Text("") // Placeholder for equals sign
                    Text("U").unitStyle()
                }
            }
            .multilineTextAlignment(.center)
            .leadingFullWidth()
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
                    GridRow(alignment: .bottom) {
                        Text("Full Bolus").secondaryLabel()
                        Text("").secondaryLabel() // Placeholder for multiplication sign
                        Text("Rec. Bolus %").secondaryLabel()
                        Spacer(minLength: 0)
                        Text("").secondaryLabel() // Placeholder for equals sign
                        Text("Result").secondaryLabel()
                    }

                    GridRow {
                        Text(insulinFormatter(state.wholeCalc)).valueStyle()
                        Text("×")
                            .font(.system(.title2, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text((100 * state.fraction).formatted()).valueStyle()
                        Spacer(minLength: 0)
                        Text("=").operatorStyle()
                        Text(insulinFormatter(state.factoredInsulin))
                            .valueStyle()
                            .foregroundStyle(addendColor(state.factoredInsulin) ?? .primary)
                    }

                    GridRow(alignment: .top) {
                        Text("U").unitStyle()
                        Text("").unitStyle() // Placeholder for multiplication sign
                        Text("/100").percentStyle()
                        Spacer(minLength: 0)
                        Text("").unitStyle() // Placeholder for equals sign
                        Text("U").unitStyle()
                    }

                case (false, true):
                    // Case: Full Bolus × Rec. Bolus % × Fatty Meal %
                    GridRow(alignment: .bottom) {
                        Text("Full Bolus").secondaryLabel()
                        Text("").secondaryLabel() // Placeholder for first multiplication sign
                        Text("Rec. Bolus %").secondaryLabel()
                        Text("").secondaryLabel() // Placeholder for second multiplication sign
                        Text("Fatty %").secondaryLabel()
                        Spacer(minLength: 0)
                        Text("").secondaryLabel() // Placeholder for equals sign
                        Text("Result").secondaryLabel()
                    }

                    GridRow {
                        Text(insulinFormatter(state.wholeCalc)).valueStyle()
                        Text("×")
                            .font(.system(.title2, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text((100 * state.fraction).formatted()).valueStyle()
                        Text("×")
                            .font(.system(.title2, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text((100 * state.fattyMealFactor).formatted()).valueStyle()
                        Spacer(minLength: 0)
                        Text("=").operatorStyle()
                        Text(insulinFormatter(state.factoredInsulin))
                            .valueStyle()
                            .foregroundStyle(addendColor(state.factoredInsulin) ?? .primary)
                    }

                    GridRow(alignment: .top) {
                        Text("U").unitStyle()
                        Text("").unitStyle() // Placeholder for first multiplication sign
                        Text("/100").percentStyle()
                        Text("").unitStyle() // Placeholder for second multiplication sign
                        Text("/100").percentStyle()
                        Spacer(minLength: 0)
                        Text("").unitStyle() // Placeholder for equals sign
                        Text("U").unitStyle()
                    }

                case (true, false):
                    // Case: (Full Bolus × Rec. Bolus %) + Super Bolus
                    GridRow(alignment: .bottom) {
                        Text("").secondaryLabel() // Placeholder for opening parenthesis
                        Text("Full Bolus").secondaryLabel()
                        Text("").secondaryLabel() // Placeholder for multiplication sign
                        Text("Rec. %").secondaryLabel()
                        Text("").secondaryLabel() // Placeholder for closing parenthesis
                        Text("").secondaryLabel() // Placeholder for plus sign
                        Text("Super Bolus").secondaryLabel()
                        Spacer(minLength: 0)
                        Text("").secondaryLabel() // Placeholder for equals sign
                        Text("Result").secondaryLabel()
                    }

                    GridRow {
                        Text("(")
                            .font(.system(.title, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(insulinFormatter(state.wholeCalc)).valueStyle()
                        Text("×")
                            .font(.system(.title2, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text((100 * state.fraction).formatted()).valueStyle()
                        Text(")")
                            .font(.system(.title, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("+")
                            .font(.system(.title2, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(insulinFormatter(state.superBolusInsulin)).valueStyle()
                        Spacer(minLength: 0)
                        Text("=").operatorStyle()
                        Text(insulinFormatter(state.factoredInsulin))
                            .valueStyle()
                            .foregroundStyle(addendColor(state.factoredInsulin) ?? .primary)
                    }

                    GridRow(alignment: .top) {
                        Text("").unitStyle() // Placeholder for opening parenthesis
                        Text("U").unitStyle()
                        Text("").unitStyle() // Placeholder for multiplication sign
                        Text("/100").percentStyle()
                        Text("").unitStyle() // Placeholder for closing parenthesis
                        Text("").unitStyle() // Placeholder for plus sign
                        Text("U").unitStyle()
                        Spacer(minLength: 0)
                        Text("").unitStyle() // Placeholder for equals sign
                        Text("U").unitStyle()
                    }

                case (true, true):
                    // This case should never occur as you can't apply a Super Bolus to a Fatty Meal
                    Text("")
                }
            }
            .multilineTextAlignment(.center)
            .trailingFullWidth()
        }
    }

    // MARK: - Result Section

    var recommendedBolusCard: some View {
        VStack {
            Text("Recommended Bolus")
                .font(.title2)
                .fontWeight(.bold)
                .minimumScaleFactor(0.5)
                .padding(.bottom, 4)

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(0.1))

                Grid(alignment: .center, horizontalSpacing: 8) {
                    let iobAvailable: Decimal = state.maxIOB - state.iob
                    let isLoopStale = state.lastLoopDate == nil ||
                        Date().timeIntervalSince(state.lastLoopDate!) > 15 * 60

                    // Main row with insulin calculation always visible
                    GridRow {
                        // Left column
                        VStack {
                            if isLoopStale {
                                limitWarning("Last loop was > 15 mins ago.")
                            } else if state.currentBG < 54 {
                                limitWarning("Glucose is very low.")
                            } else if state.minPredBG < 54 {
                                limitWarning("Glucose forecast is very low.")
                            } else if state.maxBolus <= iobAvailable, state.factoredInsulin > state.maxBolus {
                                limitWarning("Max Bolus = \(insulinFormatter(state.maxBolus)) U")
                            }

                            // Conditional rows that only appear in certain states
                            if !isLoopStale, state.factoredInsulin >= 0, state.currentBG >= 54, state.minPredBG >= 54 {
                                if !(state.maxBolus <= iobAvailable && state.factoredInsulin > state.maxBolus) {
                                    if state.factoredInsulin > iobAvailable {
                                        // Available IOB row

                                        limitWarning("Available IOB:")
                                    }

                                    // Formula row with simplified alignment
                                    HStack(alignment: .center) {
                                        let iobFormatted = state
                                            .iob < 0 ? "(\(insulinFormatter(state.iob)))" : insulinFormatter(state.iob)

                                        Text("\(insulinFormatter(state.maxIOB))")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .minimumScaleFactor(0.5)

                                        Text("-")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .minimumScaleFactor(0.5)

                                        Text("\(iobFormatted)")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .minimumScaleFactor(0.5)

                                        Text("=")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .minimumScaleFactor(0.5)

                                        Text("\(insulinFormatter(iobAvailable)) U")
                                            .font(.subheadline)
                                            .foregroundStyle(.red)
                                            .minimumScaleFactor(0.5)

                                        Spacer()
                                    }
                                    .multilineTextAlignment(.center)

                                    // Description row with simplified alignment
                                    HStack(alignment: .center) {
                                        Text("Max IOB")
                                            .tertiaryLabel()

                                        Text("")

                                        Text("IOB")
                                            .tertiaryLabel()

                                        Text("")

                                        Text("")

                                        Spacer()
                                    }
                                    .multilineTextAlignment(.center)
                                }

                                // Pump rounding note (only shown when appropriate)
                                if (state.factoredInsulin > iobAvailable && state.insulinCalculated != iobAvailable) ||
                                    state.insulinCalculated > 0
                                {
                                    Text("Rounded for pump")
                                        .secondaryLabel()
                                        .leadingFullWidth()
                                }
                            }
                        }

                        Spacer()

                        // Right column - the insulin calculation
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(insulinFormatter(state.insulinCalculated))
                                .largeValueStyle()
                                .foregroundStyle(state.insulinCalculated > 0 ? Color.accentColor : .primary)

                            Text("U")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .minimumScaleFactor(0.5)
                        }
                        .gridCellAnchor(.trailing)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
            .fixedSize(horizontal: false, vertical: true)
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

    func limitWarning(_ text: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.subheadline)

            Text(text)
                .fontWeight(.medium)
                .foregroundStyle(.red)
                .minimumScaleFactor(0.5)
                .leadingFullWidth()
                .font(.subheadline)
        }
    }

    // MARK: - Helper Methods

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
