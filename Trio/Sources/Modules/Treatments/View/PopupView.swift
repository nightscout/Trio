import SwiftUI

// MARK: - Style Extensions

private extension View {
    /// Applies secondary label styling
    func secondaryLabel() -> some View {
        font(.footnote)
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
        font(.system(.subheadline, weight: .semibold))
            .minimumScaleFactor(0.5)
    }

    /// Applies large value styling
    func largeValueStyle() -> some View {
        font(.system(.title3, weight: .bold))
            .minimumScaleFactor(0.5)
    }

    /// Applies section title styling
    func sectionTitle() -> some View {
        font(.system(.subheadline, weight: .semibold))
            .foregroundStyle(.secondary)
            .minimumScaleFactor(0.5)
    }

    /// Applies unit text styling
    func unitStyle() -> some View {
        font(.footnote)
            .foregroundStyle(.secondary)
            .minimumScaleFactor(0.5)
    }

    /// Applies to mathematical operators
    func operatorStyle() -> some View {
        font(.system(.body, weight: .regular))
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
                .padding(10)
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
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    var state: Treatments.StateModel

    @State var calcPopupDetent = PresentationDetent.large

    private var fractionDigits: Int {
        if state.units == .mmolL {
            return 1
        } else { return 0 }
    }

    private var isDeviceSmallOrTextEnlarged: Bool {
        // Check for SE-sized devices (screen width of 375 points)
        let isSmallDevice = UIScreen.main.bounds.width <= 375

        // Check if text size is larger than default (> 100%)
        let isLargeText = dynamicTypeSize > .large

        return isSmallDevice || isLargeText
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading) {
                ScrollView {
                    VStack(spacing: 20) {
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
            .navigationBarTitle(String(localized: "Bolus Calculator Details"), displayMode: .inline)
            .presentationDetents(
                [.fraction(0.9), .large],
                selection: $calcPopupDetent
            )
        }
    }

    // MARK: - Calculation Cards

    var calculationCards: some View {
        VStack(spacing: 12) {
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
        calculationCardView(String(localized: "Glucose Calculation")) {
            Grid {
                // Row 1: Titles
                GridRow(alignment: .bottom) {
                    Text("") // Placeholder for left bracket
                    Text("Current").secondaryLabel()
                    Text("") // Placeholder for minus sign
                    Text("Target").secondaryLabel()
                    Text("") // Placeholder for right bracket
                    Text("") // Placeholder for division sign
                    Text("ISF").secondaryLabel()
                    Spacer(minLength: 0)
                    Text("") // Placeholder for equals sign
                    Text("Addend").secondaryLabel()
                }

                // Row 2: Values
                GridRow {
                    Text("(").operatorStyle()
                    Text(state.units == .mmolL ? state.currentBG.formattedAsMmolL : state.currentBG.description)
                        .valueStyle()
                    Text("−").operatorStyle()
                    Text(state.units == .mmolL ? state.target.formattedAsMmolL : state.target.description)
                        .valueStyle()
                    Text(")").operatorStyle()
                    Text("/").operatorStyle()
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
                    Text("") // Placeholder for right bracket
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

    var iobCard: some View {
        calculationCardView(String(localized: "Insulin On Board (IOB)")) {
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
        calculationCardView(String(localized: "Carbs On Board (COB)")) {
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
                        .operatorStyle()
                    Text(
                        Decimal(state.cob)
                            .formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits)))
                    ).valueStyle()
                    Text("+").operatorStyle()
                    Text(
                        state.carbs
                            .formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits)))
                    ).valueStyle()
                    Text(")").operatorStyle()
                    Text("/").operatorStyle()
                    Text(state.carbRatio.formatted()).valueStyle()
                    Spacer()
                    Text("=").operatorStyle()
                    Text(exceededMaxCOB ? "" : insulinFormatter(state.wholeCobInsulin))
                        .valueStyle()
                        .foregroundStyle(addendColor(state.wholeCobInsulin) ?? .primary)
                }

                // Row 3: Units
                GridRow(alignment: .top) {
                    Text("") // Empty for opening bracket
                    Text("g").unitStyle()
                    Text("") // Empty for plus sign
                    Text("g").unitStyle()
                    Text("") // Empty for closing bracket
                    Text("") // Empty for division sign
                    Text("g/U").unitStyle()
                    Spacer()
                    Text("") // Empty for equals sign
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
                        Text("/").operatorStyle()
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
        calculationCardView(String(localized: "Glucose Trend (15 min)")) {
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
                    Text("/").operatorStyle()
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
        calculationCardView(String(localized: "Full Bolus")) {
            Grid {
                if isDeviceSmallOrTextEnlarged {
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
                        Text(wrapNegative(state.targetDifferenceInsulin))
                            .valueStyle()
                        Text("+").operatorStyle()
                        Text(wrapNegative(-1 * state.iob, .plain))
                            .valueStyle()
                        Text("+").operatorStyle()
                        Text(wrapNegative(state.wholeCobInsulin))
                            .valueStyle()
                        Text("+").operatorStyle()
                        Text(wrapNegative(state.fifteenMinInsulin))
                            .valueStyle()
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

                    Divider()

                    // Row 4: Sum
                    GridRow {
                        HStack {
                            Text("=").operatorStyle()
                            Text(insulinFormatter(state.wholeCalc))
                                .valueStyle()
                                .foregroundStyle(addendColor(state.wholeCalc) ?? .secondary)
                            Text("U").unitStyle()
                        }
                        .gridCellColumns(7)
                        .trailingFullWidth()
                    }
                } else {
                    // Row 1: Titles
                    GridRow(alignment: .bottom) {
                        Text("Glucose").secondaryLabel()
                        Text("") // Placeholder for first plus sign
                        Text("IOB").secondaryLabel()
                        Text("") // Placeholder for second plus sign
                        Text("COB").secondaryLabel()
                        Text("") // Placeholder for third plus sign
                        Text("Delta").secondaryLabel()
                        Spacer(minLength: 0)
                        Text("") // Placeholder for equals sign
                        Text("Sum").secondaryLabel()
                    }

                    // Row 2: Values
                    GridRow {
                        Text(wrapNegative(state.targetDifferenceInsulin))
                            .valueStyle()
                        Text("+").operatorStyle()
                        Text(wrapNegative(-1 * state.iob, .plain))
                            .valueStyle()
                        Text("+").operatorStyle()
                        Text(wrapNegative(state.wholeCobInsulin))
                            .valueStyle()
                        Text("+").operatorStyle()
                        Text(wrapNegative(state.fifteenMinInsulin))
                            .valueStyle()
                        Spacer(minLength: 0)
                        Text("=").operatorStyle()
                        Text(insulinFormatter(state.wholeCalc))
                            .valueStyle()
                            .foregroundStyle(addendColor(state.wholeCalc) ?? .secondary)
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
                        Spacer(minLength: 0)
                        Text("") // Placeholder for equals sign
                        Text("U").unitStyle()
                    }
                }
            }
            .multilineTextAlignment(.center)
        }
    }

    var superBolusCard: some View {
        calculationCardView(String(localized: "Super Bolus")) {
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
                    Text("×").operatorStyle()
                    Text((100 * state.sweetMealFactor).formatted() + " %").valueStyle()
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
                    Text("") // Placeholder for percent sign
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
        calculationCardView(String(localized: "Applied Factors")) {
            Grid {
                // Choose the layout based on which factors are active
                switch (state.useSuperBolus, state.useFattyMealCorrectionFactor) {
                case (false, false):
                    // Simple case: just Full Bolus × Rec. Bolus %
                    GridRow(alignment: .bottom) {
                        Text("Full Bolus").secondaryLabel()
                        Text("") // Placeholder for multiplication sign
                        Text("Rec. Bolus %").secondaryLabel()
                        Spacer(minLength: 0)
                        Text("") // Placeholder for equals sign
                        Text("Result").secondaryLabel()
                    }

                    GridRow {
                        Text(insulinFormatter(state.wholeCalc)).valueStyle()
                        Text("×").operatorStyle()
                        Text((100 * state.fraction).formatted() + " %").valueStyle()
                        Spacer(minLength: 0)
                        Text("=").operatorStyle()
                        Text(insulinFormatter(state.factoredInsulin))
                            .valueStyle()
                            .foregroundStyle(addendColor(state.factoredInsulin) ?? .primary)
                    }

                    GridRow(alignment: .top) {
                        Text("U").unitStyle()
                        Text("") // Placeholder for multiplication sign
                        Text("") // Placeholder for percent sign
                        Spacer(minLength: 0)
                        Text("") // Placeholder for equals sign
                        Text("U").unitStyle()
                    }

                case (false, true):
                    // Case: Full Bolus × Rec. Bolus % × Fatty Meal %
                    GridRow(alignment: .bottom) {
                        Text("Full Bolus").secondaryLabel()
                        Text("") // Placeholder for first multiplication sign
                        Text("Rec. Bolus %").secondaryLabel()
                        Text("") // Placeholder for second multiplication sign
                        Text("Fatty %").secondaryLabel()
                        Spacer(minLength: 0)
                        Text("") // Placeholder for equals sign
                        Text("Result").secondaryLabel()
                    }

                    GridRow {
                        Text(insulinFormatter(state.wholeCalc)).valueStyle()
                        Text("×").operatorStyle()
                        Text((100 * state.fraction).formatted() + " %").valueStyle()
                        Text("×").operatorStyle()
                        Text((100 * state.fattyMealFactor).formatted() + " %").valueStyle()
                        Spacer(minLength: 0)
                        Text("=").operatorStyle()
                        Text(insulinFormatter(state.factoredInsulin))
                            .valueStyle()
                            .foregroundStyle(addendColor(state.factoredInsulin) ?? .primary)
                    }

                    GridRow(alignment: .top) {
                        Text("U").unitStyle()
                        Text("") // Placeholder for first multiplication sign
                        Text("") // Placeholder for percent sign
                        Text("") // Placeholder for second multiplication sign
                        Text("") // Placeholder for percent sign
                        Spacer(minLength: 0)
                        Text("") // Placeholder for equals sign
                        Text("U").unitStyle()
                    }

                case (true, false):
                    // Case: (Full Bolus × Rec. Bolus %) + Super Bolus
                    GridRow(alignment: .bottom) {
                        Text("") // Placeholder for opening parenthesis
                        Text("Full Bolus").secondaryLabel()
                        Text("") // Placeholder for multiplication sign
                        Text("Rec. %").secondaryLabel()
                        Text("") // Placeholder for closing parenthesis
                        Text("") // Placeholder for plus sign
                        Text("Super Bolus").secondaryLabel()
                        Spacer(minLength: 0)
                        Text("") // Placeholder for equals sign
                        Text("Result").secondaryLabel()
                    }

                    GridRow {
                        Text("(").operatorStyle()
                        Text(insulinFormatter(state.wholeCalc)).valueStyle()
                        Text("×").operatorStyle()
                        Text((100 * state.fraction).formatted() + " %").valueStyle()
                        Text(")").operatorStyle()
                        Text("+").operatorStyle()
                        Text(insulinFormatter(state.superBolusInsulin)).valueStyle()
                        Spacer(minLength: 0)
                        Text("=").operatorStyle()
                        Text(insulinFormatter(state.factoredInsulin))
                            .valueStyle()
                            .foregroundStyle(addendColor(state.factoredInsulin) ?? .primary)
                    }

                    GridRow(alignment: .top) {
                        Text("") // Placeholder for opening parenthesis
                        Text("U").unitStyle()
                        Text("") // Placeholder for multiplication sign
                        Text("") // Placeholder for percent sign
                        Text("") // Placeholder for closing parenthesis
                        Text("") // Placeholder for plus sign
                        Text("U").unitStyle()
                        Spacer(minLength: 0)
                        Text("") // Placeholder for equals sign
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
                .font(.headline)
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
                                limitWarning(String(localized: "Last loop was > 15 mins ago."))
                            } else if state.currentBG < 54 {
                                limitWarning(String(localized: "Glucose is very low."))
                            } else if state.minPredBG < 54 {
                                limitWarning(String(localized: "Glucose forecast is very low."))
                            } else if state.factoredInsulin > state.maxBolus, state.maxBolus <= iobAvailable {
                                limitWarning(String(localized: "Max Bolus = \(insulinFormatter(state.maxBolus)) U"))
                            } else if state.factoredInsulin > 0 {
                                if state.factoredInsulin > iobAvailable {
                                    // Available IOB row
                                    limitWarning(String(localized: "Available IOB:"))

                                    // Formula row with simplified alignment
                                    HStack(alignment: .center) {
                                        let iobFormatted = state.iob < 0 ?
                                            "(\(insulinFormatter(state.iob)))" : insulinFormatter(state.iob)

                                        Text("\(insulinFormatter(state.maxIOB))").valueStyle()
                                        Text("-").operatorStyle()
                                        Text("\(iobFormatted)").valueStyle()
                                        Text("=").operatorStyle()
                                        Text("\(insulinFormatter(iobAvailable)) U")
                                            .font(.subheadline)
                                            .foregroundStyle(.red)
                                            .minimumScaleFactor(0.5)
                                        Spacer()
                                    }
                                    .multilineTextAlignment(.center)

                                    // Description row with simplified alignment
                                    HStack(alignment: .center) {
                                        Text("Max IOB").tertiaryLabel()
                                        Text("")
                                        Text("IOB").tertiaryLabel()
                                        Text("")
                                        Text("")
                                        Spacer()
                                    }
                                    .multilineTextAlignment(.center)
                                }

                                // Pump rounding note (only shown when appropriate)
                                if (
                                    state.factoredInsulin > iobAvailable &&
                                        insulinFormatter(state.insulinCalculated) != insulinFormatter(iobAvailable)
                                ) || (
                                    state.factoredInsulin <= iobAvailable &&
                                        insulinFormatter(state.insulinCalculated) != insulinFormatter(state.factoredInsulin)
                                )
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
        VStack(alignment: .leading, spacing: 4) {
            Text(title).sectionTitle()
            content().calculationCardStyle()
        }
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

    func wrapNegative(_ value: Decimal, _ roundingMode: NSDecimalNumber.RoundingMode = .down) -> String {
        value < 0 ? "(" + insulinFormatter(value, roundingMode) + ")" : insulinFormatter(value, roundingMode)
    }
}
