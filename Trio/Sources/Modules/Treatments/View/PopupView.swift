import SwiftUI

// MARK: - Style Extensions

// View modifiers that provide consistent styling across calculation components.
// These extensions establish a visual hierarchy through font sizing, coloring, and layout priorities.

private extension View {
    /// Applies secondary label styling for descriptive text elements.
    /// Uses a smaller font with secondary color to visually distinguish labels from values.
    /// Layout priority ensures these elements maintain appropriate space.
    func secondaryStyle() -> some View {
        font(.footnote)
            .foregroundStyle(.secondary)
            .allowsTightening(true)
            .minimumScaleFactor(0.5)
            .layoutPriority(1)
    }

    /// Applies unit label styling for measurement units (mg/dL, mmol/L, U, g, etc.)
    /// Uses the smallest font size with secondary color to de-emphasize units.
    /// Low layout priority ensures units don't compete for space with values.
    func unitStyle() -> some View {
        font(.caption2)
            .foregroundStyle(.secondary)
            .allowsTightening(true)
            .minimumScaleFactor(0.5)
            .layoutPriority(-1)
    }

    /// Applies mathematical operator label styling (+, -, ×, ÷, =, etc.)
    /// Medium priority ensures operators maintain proper spacing between values
    /// while allowing compression when space is limited.
    func operatorStyle() -> some View {
        font(.body)
            .foregroundStyle(.secondary)
            .allowsTightening(true)
            .minimumScaleFactor(0.5)
            .layoutPriority(3)
    }

    /// Applies styling for numeric values in calculations.
    /// Higher layout priority (5) ensures values maintain visibility when space is constrained.
    /// Minimum width prevents values from becoming too compressed.
    func valueStyle() -> some View {
        font(.headline)
            .frame(minWidth: 50)
            .allowsTightening(true)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .layoutPriority(5)
    }

    /// Applies styling for calculation results with dynamic coloring based on value.
    /// - Parameter value: The numeric value to display, which determines color:
    ///   - Negative values: Red (indicating insulin reduction)
    ///   - Zero: Primary color
    ///   - Positive values: Green (indicating insulin addition)
    /// Highest layout priority (10) ensures results remain visible even in constrained layouts.
    func solutionStyle(_ value: Decimal = 0) -> some View {
        let solutionColor: Color
        switch value {
        case ..<0:
            solutionColor = .red
        case 0:
            solutionColor = .primary
        default:
            solutionColor = .green
        }

        return font(.system(.headline, weight: .bold))
            .frame(minWidth: 45, alignment: .center)
            .foregroundStyle(solutionColor)
            .allowsTightening(true)
            .fixedSize(horizontal: true, vertical: true)
            .minimumScaleFactor(0.5)
            .layoutPriority(10)
            .lineLimit(1)
    }

    /// Applies styling for the final recommendation value.
    /// Uses larger font size than regular solutions to emphasize the final result.
    /// Maintains highest layout priority to ensure visibility.
    func largeSolutionStyle() -> some View {
        font(.system(.title3, weight: .bold))
            .allowsTightening(true)
            .fixedSize(horizontal: true, vertical: true)
            .minimumScaleFactor(0.5)
            .layoutPriority(10)
            .lineLimit(1)
    }

    /// Applies styling for warning labels.
    /// - Parameter warningColor: The color of the text.
    func warningStyle(_ warningColor: Color) -> some View {
        font(.subheadline)
            .foregroundStyle(warningColor)
            .allowsTightening(true)
            .minimumScaleFactor(0.5)
    }

    /// Reduces the default inset padding of List Sections for more compact presentation.
    /// Creates tighter spacing in the calculation cards.
    func listRowStyle() -> some View {
        listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
    }
}

// MARK: - Main PopupView

// A detailed view presenting all components of the bolus calculation.
// Displays breakdown of calculations in separate cards within a scrollable list,
// with a sticky recommendation card at the bottom.

struct PopupView: View {
    @Environment(\.colorScheme) var colorScheme

    /// State model containing all calculation parameters and results.
    var state: Treatments.StateModel

    /// Controls the preferred presentation size of the popup.
    @State private var calcPopupDetent = PresentationDetent.large

    /// Trigger for flashing scroll indicators when view appears.
    /// Helps users discover scrollable content.
    @State private var shouldFlashScroll = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .center) {
                // List of calculation cards organized in sections.
                // Each section represents a component of the final calculation.
                List {
                    Section("Glucose Calculation") {
                        glucoseCardContent.listRowStyle()
                    }
                    Section("Insulin On Board (IOB)") {
                        iobCardContent.listRowStyle()
                    }
                    Section("Carbs On Board (COB)") {
                        cobCardContent.listRowStyle()
                    }
                    Section("Glucose Trend (15 min)") {
                        deltaCardContent.listRowStyle()
                    }
                    Section("Full Bolus") {
                        fullBolusCardContent.listRowStyle()
                    }

                    // Conditional sections based on user's selection of the "Super Bolus" option.
                    if state.useSuperBolus {
                        Section("Super Bolus") {
                            superBolusCardContent.listRowStyle()
                        }
                    }

                    // If the solution of this card does not recommend any insulin,
                    // there's no point in showing it
                    if state.factoredInsulin > 0 {
                        Section("Applied Factors") {
                            factorsCardContent.listRowStyle()
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .listStyle(InsetGroupedListStyle())
                .listSectionSpacing(0)
                .scrollIndicatorsFlash(trigger: shouldFlashScroll)
                .onAppear {
                    // Flash scroll indicators after a short delay to help users discover scrollable content.
                    // The delay allows the sheet presentation animation to complete first.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        shouldFlashScroll = true
                    }
                }

                // Sticky footer with recommendation and dismiss button.
                // Remains visible regardless of scroll position.
                VStack(alignment: .center, spacing: 10) {
                    recommendedBolusCard

                    Button {
                        state.showInfo = false
                    } label: {
                        Text("Got it!").bold()
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.bordered)
                }
                .padding([.horizontal, .bottom])
            }
            .navigationBarTitle(String(localized: "Bolus Calculator Details"), displayMode: .inline)
            .presentationDetents(
                [.fraction(0.9), .large],
                selection: $calcPopupDetent
            )
        }
    }

    // MARK: - Calculation Card Contents

    // Each card visualizes a specific component of the bolus calculation.
    // The cards use Grid layout to show mathematical formulas with proper alignment
    // of the variable's name as the header and the units used as the footer.
    // Inifinity frame on "=" operator aligns the formula to the left and the solution to the right of the row.

    /// Card showing insulin required to get current glucose to the target glucose based on insulin sensitivity.
    /// Formula: (Current Glucose - Target Glucose) / ISF = Glucose Correction Dose
    private var glucoseCardContent: some View {
        Grid(alignment: .center) {
            // Row 1: Column headers for the calculation components
            GridRow(alignment: .lastTextBaseline) {
                Text("Current")
                    .gridCellColumns(3) // Allows label to expand above operators.
                Text("Target")
                Text("")
                    .layoutPriority(-15)
                    .gridCellColumns(2)
                Text("ISF")
            }
            .secondaryStyle()

            // Row 2: The calculation formula with values and operators
            GridRow {
                Text("(")
                    .operatorStyle()
                Text(state.units == .mmolL ? state.currentBG.formattedAsMmolL : state.currentBG.description)
                    .valueStyle()
                Text("−")
                    .operatorStyle()
                Text(state.units == .mmolL ? state.target.formattedAsMmolL : state.target.description)
                    .valueStyle()
                Text(")")
                    .operatorStyle()
                Text("/")
                    .operatorStyle()
                Text(state.units == .mmolL ? state.isf.formattedAsMmolL : state.isf.description)
                    .valueStyle()
                Text("=")
                    .operatorStyle()
                    .frame(idealWidth: 10, maxWidth: .infinity, alignment: .trailing)
                    .layoutPriority(-15)
                Text(insulinFormatter(state.targetDifferenceInsulin))
                    .solutionStyle(state.targetDifferenceInsulin)
            }

            // Row 3: Units for each value
            GridRow(alignment: .firstTextBaseline) {
                Text(state.units.rawValue)
                    .gridCellColumns(3) // Allows cell to expand below operators.
                Text(state.units.rawValue)
                Text("")
                    .layoutPriority(-15)
                    .gridCellColumns(2)
                Text("\(state.units.rawValue)/U")
                Text("")
                    .layoutPriority(-15)
                Text("U")
            }
            .unitStyle()
        }
        .multilineTextAlignment(.center)
    }

    /// Card showing offset of current insulin on board (IOB).
    /// If current IOB is already positive, reduce the insulin recommendation,
    /// but if negative then increase the insulin recommendation.
    /// Formula: -1 × Current IOB = IOB Correction Dose
    private var iobCardContent: some View {
        Grid(alignment: .center) {
            // Row 1: Column header
            GridRow(alignment: .lastTextBaseline) {
                Text("")
                    .layoutPriority(-15)
                    .gridCellColumns(2)
                Text("IOB")
            }
            .secondaryStyle()

            // Row 2: The IOB calculation formula
            GridRow {
                Text("-1")
                    .valueStyle()
                Text("×")
                    .operatorStyle()
                Text(insulinFormatter(state.iob, .plain)) // Use .plain rounding to match inverted value.
                    .valueStyle()
                Text("=").operatorStyle()
                    .frame(idealWidth: 10, maxWidth: .infinity, alignment: .trailing)
                    .layoutPriority(-15)
                Text(insulinFormatter(-1 * state.iob, .plain)) // Use .plain rounding to match inverted value.
                    .solutionStyle(-1 * state.iob)
            }

            // Row 3: Units
            GridRow(alignment: .firstTextBaseline) {
                Text("")
                    .layoutPriority(-15)
                    .gridCellColumns(2)
                Text("U")
                Text("")
                    .layoutPriority(-15)
                Text("U")
            }
            .unitStyle()
        }
        .multilineTextAlignment(.center)
    }

    /// Card showing insulin required to offset meals. Combine current carbs on board (COB)
    /// with new carbs entered in the Treatment view and divide by the carb ratio.
    /// Don't allow total carbs to exceed Max IOB setting.
    /// Formula: (Current COB + New Carbs) / Carb Ratio = COB Correction Dose
    private var cobCardContent: some View {
        let hasExceededMaxCOB: Bool = Decimal(state.cob) + state.carbs > state.maxCOB
        return Group {
            Grid(alignment: .center) {
                // Row 1: Column headers for the COB calculation
                GridRow(alignment: .lastTextBaseline) {
                    Text("")
                        .layoutPriority(-15)
                    Text("COB")
                    Text("Carbs")
                        .gridCellColumns(3) // Allows label to expand above operators.
                    Text("")
                        .layoutPriority(-15)
                    Text("CR")
                }
                .secondaryStyle()

                // Row 2: The full COB calculation formula
                // Don't include solution when Max IOB has been exceeded
                GridRow {
                    Text("(")
                        .operatorStyle()
                    Text(Int(state.cob).description)
                        .valueStyle()
                    Text("+")
                        .operatorStyle()
                    Text(Int(state.carbs).description)
                        .valueStyle()
                    Text(")")
                        .operatorStyle()
                    Text("/")
                        .operatorStyle()
                    Text(state.carbRatio.formatted())
                        .valueStyle()
                    Text("=")
                        .operatorStyle()
                        .frame(idealWidth: 10, maxWidth: .infinity, alignment: .trailing)
                        .layoutPriority(-15)
                    if !hasExceededMaxCOB {
                        Text(insulinFormatter(state.wholeCobInsulin))
                            .solutionStyle(state.wholeCobInsulin)
                    }
                }

                // Row 3: Units for each component
                // Don't show solution's unit if Max COB has been exceeded
                GridRow(alignment: .firstTextBaseline) {
                    Text("")
                        .layoutPriority(-15)
                    Text("g")
                    Text("")
                        .layoutPriority(-15)
                    Text("g")
                    Text("")
                        .layoutPriority(-15)
                        .gridCellColumns(2)
                    Text("g/U")
                    if !hasExceededMaxCOB {
                        Text("")
                            .layoutPriority(-15)
                        Text("U")
                    }
                }
                .unitStyle()
            }
            .multilineTextAlignment(.center)

            // Additional grid only displayed when Max COB limit has been exceeded
            if hasExceededMaxCOB {
                Grid(alignment: .center) {
                    // Row 4: Alternative calculation headers (max COB)
                    GridRow(alignment: .lastTextBaseline) {
                        Text("Max COB")
                        Text("")
                            .layoutPriority(-15)
                        Text("CR")
                    }
                    .secondaryStyle()

                    // Row 5: Alternative calculation with max COB
                    // Shows: Max COB / Carb Ratio = Limited COB Insulin
                    GridRow {
                        Text(Int(state.wholeCob).description)
                            .valueStyle()
                            .foregroundStyle(.orange)
                        Text("/")
                            .operatorStyle()
                        Text(state.carbRatio.formatted())
                            .valueStyle()
                        Text("=").operatorStyle()
                            .frame(idealWidth: 10, maxWidth: .infinity, alignment: .trailing)
                            .layoutPriority(-15)
                        Text(insulinFormatter(state.wholeCobInsulin))
                            .solutionStyle(state.wholeCobInsulin)
                    }

                    // Row 6: Units for max COB calculation
                    GridRow(alignment: .firstTextBaseline) {
                        Text("g")
                        Text("")
                            .layoutPriority(-15)
                        Text("g/U")
                        Text("")
                            .layoutPriority(-15)
                        Text("U")
                    }
                    .unitStyle()
                }
                .multilineTextAlignment(.center)
            }
        }
    }

    /// Card showing inslin required to offset glucose trend from past 15 minutes
    /// Formula: Change in Glucose / ISF = Glucose Trend Correction Dose
    private var deltaCardContent: some View {
        Grid(alignment: .center) {
            // Row 1: Column headers
            GridRow(alignment: .lastTextBaseline) {
                Text("Delta")
                Text("")
                    .layoutPriority(-15)
                Text("ISF")
            }
            .secondaryStyle()

            // Row 2: The delta calculation formula
            GridRow {
                Text(state.units == .mmolL ? state.deltaBG.formattedAsMmolL : state.deltaBG.description)
                    .valueStyle()
                Text("/")
                    .operatorStyle()
                Text(state.units == .mmolL ? state.isf.formattedAsMmolL : state.isf.description)
                    .valueStyle()
                Text("=")
                    .operatorStyle()
                    .frame(idealWidth: 10, maxWidth: .infinity, alignment: .trailing)
                    .layoutPriority(-15)
                Text(insulinFormatter(state.fifteenMinInsulin))
                    .solutionStyle(state.fifteenMinInsulin)
            }

            // Row 3: Units for each component
            GridRow(alignment: .firstTextBaseline) {
                Text(state.units.rawValue)
                Text("")
                    .layoutPriority(-15)
                Text("\(state.units.rawValue)/U")
                Text("")
                    .layoutPriority(-15)
                Text("U")
            }
            .unitStyle()
        }
        .multilineTextAlignment(.center)
    }

    /// Card showing combined calculation for full bolus (before factors)
    /// Combines all four individual components into a single dose.
    /// Formula: Glucose Dose + IOB Dose + COB Dose + Delta Dose = Full Bolus
    private var fullBolusCardContent: some View {
        Group {
            Grid(alignment: .center, horizontalSpacing: 1) {
                // Row 1: Column headers
                GridRow(alignment: .lastTextBaseline) {
                    Text("Glucose")
                    Text("")
                        .layoutPriority(-15)
                    Text("IOB")
                    Text("")
                        .layoutPriority(-15)
                    Text("COB")
                    Text("")
                        .layoutPriority(-15)
                    Text("Delta")
                }
                .secondaryStyle()

                // Row 2: The full bolus calculation formula components. (Values only.)
                // Infinity frames on operators distributes the formula across the entire row.
                GridRow {
                    Text(wrapNegative(state.targetDifferenceInsulin))
                        .valueStyle()
                    Text("+")
                        .operatorStyle()
                        .frame(maxWidth: .infinity)
                    Text(wrapNegative(-1 * state.iob, .plain))
                        .valueStyle()
                    Text("+")
                        .operatorStyle()
                        .frame(maxWidth: .infinity)
                    Text(wrapNegative(state.wholeCobInsulin))
                        .valueStyle()
                    Text("+")
                        .operatorStyle()
                        .frame(maxWidth: .infinity)
                    Text(wrapNegative(state.fifteenMinInsulin))
                        .valueStyle()
                }

                // Row 3: Units for each component.
                GridRow(alignment: .firstTextBaseline) {
                    Text("U")
                    Text("")
                        .layoutPriority(-15)
                    Text("U")
                    Text("")
                        .layoutPriority(-15)
                    Text("U")
                    Text("")
                        .layoutPriority(-15)
                    Text("U")
                }
                .unitStyle()
            }
            .multilineTextAlignment(.center)

            // Row 4: Sum/total of all components, aligned right.
            HStack(alignment: .center, spacing: 4) {
                Spacer()
                Text("=")
                    .operatorStyle()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(insulinFormatter(state.wholeCalc))
                        .solutionStyle(state.wholeCalc)
                    Text("U")
                        .secondaryStyle()
                }
            }
        }
    }

    /// Card showing Super Bolus calculation (if selected by user).
    /// Converts a portion of basal insulin into immediate bolus for stronger bolus recommendation.
    /// Formula: Basal Rate × Super Bolus % = Super Bolus Insulin
    private var superBolusCardContent: some View {
        Grid(alignment: .center) {
            // Row 1: Column headers.
            GridRow(alignment: .lastTextBaseline) {
                Text("Basal Rate")
                Text("")
                    .layoutPriority(-15)
                Text("Super Bolus %")
                    .frame(minWidth: 90) // Discourages wrapping this cell into multiple lines.
            }
            .secondaryStyle()

            // Row 2: The super bolus calculation formula.
            GridRow {
                Text("\(state.currentBasal)")
                    .valueStyle()
                Text("×")
                    .operatorStyle()
                Text((100 * state.sweetMealFactor).formatted() + " %")
                    .valueStyle()
                Text("=").operatorStyle()
                    .frame(idealWidth: 10, maxWidth: .infinity, alignment: .trailing)
                    .layoutPriority(-15)
                Text(insulinFormatter(state.superBolusInsulin))
                    .solutionStyle(state.superBolusInsulin)
            }

            // Row 3: Units for each component.
            GridRow(alignment: .firstTextBaseline) {
                Text("U/hr")
                Text("")
                    .layoutPriority(-15)
                    .gridCellColumns(3)
                Text("U")
            }
            .unitStyle()
        }
        .multilineTextAlignment(.center)
    }

    /// Card showing applied factors to the final insulin calculation.
    /// Dynamically changes card based on user's selection in the Treatment view.
    /// User can choose Fatty Meal, Super Bolus, or neither, but not both.
    private var factorsCardContent: some View {
        Grid(alignment: .center) {
            // Choose the layout based on which options are selected
            switch (state.useSuperBolus, state.useFattyMealCorrectionFactor) {
            // Simple case: just Full Bolus × Rec. Bolus %
            case (false, false):
                // Row 1: Header.
                GridRow(alignment: .lastTextBaseline) {
                    Text("Full Bolus")
                    Text("")
                        .layoutPriority(-15)
                    Text("Rec. Bolus %")
                }
                .secondaryStyle()

                // Row 2: Formula.
                GridRow {
                    Text(insulinFormatter(state.wholeCalc))
                        .valueStyle()
                    Text("×")
                        .operatorStyle()
                    Text((100 * state.fraction).formatted() + " %")
                        .valueStyle()
                    Text("=")
                        .operatorStyle()
                        .frame(idealWidth: 10, maxWidth: .infinity, alignment: .trailing)
                        .layoutPriority(-15)
                    Text(insulinFormatter(state.factoredInsulin))
                        .solutionStyle(state.factoredInsulin)
                }

                // Row 3: Units.
                GridRow(alignment: .firstTextBaseline) {
                    Text("U")
                    Text("")
                        .layoutPriority(-15)
                        .gridCellColumns(3)
                    Text("U")
                }
                .unitStyle()

            // Case: Full Bolus × Rec. Bolus % × Fatty Meal %
            case (false, true):
                // Row 1: Header.
                GridRow(alignment: .lastTextBaseline) {
                    Text("Full Bolus")
                    Text("")
                        .layoutPriority(-15)
                    Text("Rec. Bolus %")
                    Text("")
                        .layoutPriority(-15)
                    Text("Fatty %")
                }
                .secondaryStyle()

                // Row 2: Formula.
                GridRow {
                    Text(insulinFormatter(state.wholeCalc)).valueStyle()
                    Text("×")
                        .operatorStyle()
                    Text((100 * state.fraction).formatted() + " %")
                        .valueStyle()
                    Text("×")
                        .operatorStyle()
                    Text((100 * state.fattyMealFactor).formatted() + " %")
                        .valueStyle()
                    Text("=")
                        .operatorStyle()
                        .frame(idealWidth: 10, maxWidth: .infinity, alignment: .trailing)
                        .layoutPriority(-15)
                    Text(insulinFormatter(state.factoredInsulin))
                        .solutionStyle(state.factoredInsulin)
                }

                // Row 3: Units.
                GridRow(alignment: .firstTextBaseline) {
                    Text("U")
                    Text("")
                        .layoutPriority(-15)
                    Text("U")
                }
                .unitStyle()

            // Case: (Full Bolus × Rec. Bolus %) + Super Bolus
            case (true, false):
                if state.wholeCalc > 0 {
                    // Row 1: Header.
                    GridRow(alignment: .lastTextBaseline) {
                        Text("Full Bolus")
                            .gridCellColumns(3) // Allows label to expand above operators.
                        Text("Rec. %")
                        Text("")
                            .layoutPriority(-15)
                            .gridCellColumns(2)
                        Text("Super Bolus")
                    }
                    .secondaryStyle()

                    // Row 2: Formula.
                    GridRow {
                        Text("(")
                            .operatorStyle()
                        Text(insulinFormatter(state.wholeCalc)).valueStyle()
                        Text("×")
                            .operatorStyle()
                        Text((100 * state.fraction).formatted() + " %")
                            .valueStyle()
                        Text(")")
                            .operatorStyle()
                        Text("+")
                            .operatorStyle()
                        Text(insulinFormatter(state.superBolusInsulin))
                            .valueStyle()
                        Text("=")
                            .operatorStyle()
                            .frame(idealWidth: 10, maxWidth: .infinity, alignment: .trailing)
                            .layoutPriority(-15)
                        Text(insulinFormatter(state.factoredInsulin))
                            .solutionStyle(state.factoredInsulin)
                    }

                    // Row 3: Units.
                    GridRow(alignment: .firstTextBaseline) {
                        Text("")
                            .layoutPriority(-15)
                        Text("U")
                        Text("")
                            .layoutPriority(-15)
                            .gridCellColumns(4)
                        Text("U")
                        Text("")
                            .layoutPriority(-15)
                        Text("U")
                    }
                    .unitStyle()
                } else {
                    // Row 1: Header.
                    GridRow(alignment: .lastTextBaseline) {
                        Text("Full Bolus")
                        Text("")
                            .layoutPriority(-15)
                        Text("Super Bolus")
                    }
                    .secondaryStyle()

                    // Row 2: Formula.
                    GridRow {
                        Text(insulinFormatter(state.wholeCalc)).valueStyle()
                        Text("+")
                            .operatorStyle()
                        Text(insulinFormatter(state.superBolusInsulin))
                            .valueStyle()
                        Text("=")
                            .operatorStyle()
                            .frame(idealWidth: 10, maxWidth: .infinity, alignment: .trailing)
                            .layoutPriority(-15)
                        Text(insulinFormatter(state.factoredInsulin))
                            .solutionStyle(state.factoredInsulin)
                    }

                    // Row 3: Units.
                    GridRow(alignment: .firstTextBaseline) {
                        Text("U")
                        Text("")
                            .layoutPriority(-15)
                        Text("U")
                        Text("")
                            .layoutPriority(-15)
                        Text("U")
                    }
                    .unitStyle()
                }

            // This case should never occur as you can't apply a Super Bolus to a Fatty Meal
            // Per app logic, these options are mutually exclusive
            case (true, true):
                Text("")
                    .layoutPriority(-15)
            }
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Result Section

    // Final recommendation display with warning conditions and limitations

    /// Recommended bolus card that stays fixed at bottom of the view
    /// Displays final calculated insulin amount with warnings based on various conditions:
    /// - Loop staleness
    /// - Very low glucose (current or forecasted)
    /// - Max bolus limits
    /// - Available IOB limits
    private var recommendedBolusCard: some View {
        /// Amount of insulin that can be dosed without exceeding Max IOB.
        let iobAvailable: Decimal = state.maxIOB - state.iob
        /// Checks if last loop was over 15 minutes ago.
        let isLoopStale = state.lastLoopDate == nil ||
            Date().timeIntervalSince(state.lastLoopDate!) > 15 * 60

        /// Computed property to determine if pump-compatible rounding was applied.
        /// Only relevant for positive insulin amounts.
        var isRoundedForPump: Bool {
            // Only check for rounding when we have a positive recommendation amount.
            if state.factoredInsulin > 0 {
                if state.factoredInsulin > iobAvailable {
                    // Check if calculated insulin appears different from available IOB (limited by Max IOB)
                    return insulinFormatter(state.insulinCalculated) != insulinFormatter(iobAvailable)
                } else {
                    // Check if calculated insulin appears different from factored insulin (normal case)
                    return insulinFormatter(state.insulinCalculated) != insulinFormatter(state.factoredInsulin)
                }
            }
            return false
        }

        return VStack(alignment: .center, spacing: 4) {
            let warningColor: Color = colorScheme == .dark ? .orange : .accentColor

            // Display appropriate warnings based on current conditions as a header on this card.
            // Each warning indicates a specific safety concern.
            if isLoopStale {
                Text("Last loop was > 15 m ago.")
                    .warningStyle(warningColor)
            } else if state.currentBG < 54 {
                Text("Glucose is very low.")
                    .warningStyle(.red)
            } else if state.minPredBG < 54 {
                Text("Glucose forecast is very low.")
                    .warningStyle(warningColor)
            } else if state.factoredInsulin > state.maxBolus, state.maxBolus <= iobAvailable {
                Text("Max Bolus = \(insulinFormatter(state.maxBolus)) U")
                    .warningStyle(warningColor)
            } else if state.factoredInsulin > 0, state.factoredInsulin > iobAvailable {
                // Available IOB warning with detailed breakdown.
                // Shows calculation: Max IOB - IOB = Available IOB
                if state.iob > state.maxIOB {
                    Text("Current IOB (\(insulinFormatter(state.iob)) U) > Max IOB (\(insulinFormatter(state.maxIOB)) U)")
                        .warningStyle(warningColor)
                } else {
                    Text("Limited by Max IOB.")
                        .warningStyle(warningColor)
                    ViewThatFits(in: .horizontal) {
                        // Option 1: Everything on one line (preferred if it fits)
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text("Max IOB (")
                            Text(insulinFormatter(state.maxIOB))
                                .foregroundStyle(.primary)
                            Text(" U) - Current IOB (")
                            Text(insulinFormatter(state.iob))
                                .foregroundStyle(.primary)
                            Text(" U) = ")
                            Text(insulinFormatter(iobAvailable))
                                .foregroundStyle(.orange)
                            Text(" U")
                        }

                        // Option 2: Two lines
                        Grid {
                            GridRow {
                                Text("Max IOB")
                                Text("")
                                Text("IOB")
                                Text("")
                                Text("Limit")
                            }
                            GridRow {
                                HStack(alignment: .firstTextBaseline, spacing: 0) {
                                    Text(insulinFormatter(state.maxIOB))
                                        .foregroundStyle(.primary)
                                    Text(" U")
                                }
                                Text("-")
                                HStack(alignment: .firstTextBaseline, spacing: 0) {
                                    Text(wrapNegative(state.iob))
                                        .foregroundStyle(.primary)
                                    Text(" U")
                                }
                                Text("=")
                                HStack(alignment: .firstTextBaseline, spacing: 0) {
                                    Text(insulinFormatter(iobAvailable))
                                        .foregroundStyle(.orange)
                                    Text(" U")
                                }
                            }
                        }
                    }
                    .secondaryStyle()
                }
            }

            // Recommended Bolus card with accent-colored background
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(0.1))

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recommended Bolus").font(.headline)

                        // Only show "Rounded for pump" text when rounding was applied.
                        if isRoundedForPump {
                            Text("Rounded for pump")
                                .secondaryStyle()
                        }
                    }
                    .fixedSize(horizontal: true, vertical: true)

                    Spacer()

                    // Final insulin recommendation
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(insulinFormatter(state.insulinCalculated))
                            .largeSolutionStyle()
                            .foregroundStyle(state.insulinCalculated > 0 ? Color.accentColor : .primary)

                        Text("U")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Helper Formatters

    // Functions for consistent number formatting throughout the view

    /// Formats insulin values with consistent decimal places
    /// - Parameters:
    ///   - value: The insulin value to format
    ///   - roundingMode: The rounding mode to apply (default: .down for conservative dosing)
    /// - Returns: A formatted string with 2 decimal places
    private func insulinFormatter(_ value: Decimal, _ roundingMode: NSDecimalNumber.RoundingMode = .down) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.locale = Locale.current

        // Create a decimal handler with the specified rounding behavior.
        // Always rounds to 2 decimal places (0.01 U precision).
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

    /// Wraps negative values in parentheses for clearer display in full bolus card.
    /// - Parameters:
    ///   - value: The decimal value to format
    ///   - roundingMode: The rounding mode to apply (default: .down)
    /// - Returns: A formatted string with parentheses for negative values
    private func wrapNegative(_ value: Decimal, _ roundingMode: NSDecimalNumber.RoundingMode = .down) -> String {
        value < 0 ? "(" + insulinFormatter(value, roundingMode) + ")" : insulinFormatter(value, roundingMode)
    }
}
