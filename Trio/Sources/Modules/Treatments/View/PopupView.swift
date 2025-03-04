import SwiftUI

struct PopupView: View {
    var state: Treatments.StateModel
    @Environment(\.colorScheme) var colorScheme

    private var fractionDigits: Int {
        if state.units == .mmolL {
            return 1
        } else { return 0 }
    }

    var body: some View {
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

                    DividerCustom(2)

                    calcFullBolusRow

                    if state.useSuperBolus {
                        DividerCustom()
                        calcSuperBolusRow
                        calcSuperBolusFormulaRow
                    }

                    DividerDouble()

                    if state.factoredInsulin > 0 {
                        calcResultRow
                        calcResultFormulaRow
                        DividerCustom()
                    }

                    GridRow {
                        Text("Recommended Bolus")
                            .gridCellColumns(3)
                            .gridCellAnchor(.center)
                            .padding(.bottom, 10)
                    }
                    limitsRow
                }
            }
            .padding([.horizontal, .bottom])
            .font(.subheadline)
            .safeAreaInset(edge: .bottom) {
                Button { state.showInfo = false }
                label: { Text("Got it!").bold().frame(maxWidth: .infinity, minHeight: 30, alignment: .center) }
                    .buttonStyle(.bordered)
                    .padding(.horizontal)
                    .background(Color(UIColor.systemBackground))
            }
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
            Text(state.carbRatio.formatted() + " " + String(localized: "g/U", comment: " grams per Unit"))
                .gridCellAnchor(.leading)

            let isf = state.units == .mmolL ? state.isf.formattedAsMmolL : state.isf.description
            Text(
                isf + " " + state.units
                    .rawValue + String(localized: "/U", comment: "/Insulin unit")
            ).gridCellAnchor(.leading)

            let target = state.units == .mmolL ? state.target.formattedAsMmolL : state.target.description
            Text(
                target +
                    " " + state.units.rawValue
            ).gridCellAnchor(.leading)
        }
    }

    var calcGlucoseFirstRow: some View {
        GridRow(alignment: .center) {
            let currentBG = state.units == .mmolL ? state.currentBG.formattedAsMmolL : state.currentBG.description
            let target = state.units == .mmolL ? state.target.formattedAsMmolL : state.target.description

            Text("Glucose:").foregroundColor(.secondary)

            let targetDifference = state.units == .mmolL ? state.targetDifference.formattedAsMmolL : state.targetDifference
                .description
            let firstRow = currentBG
                + " - " +
                target
                + " = " +
                targetDifference

            Text(firstRow).frame(minWidth: 0, alignment: .leading).foregroundColor(.secondary)
                .gridColumnAlignment(.leading)

            HStack {
                Text(
                    self.insulinFormatter(state.targetDifferenceInsulin)
                )
                Text("U").foregroundColor(.secondary)
            }.fontWeight(.bold)
                .gridColumnAlignment(.trailing)
        }
    }

    var calcGlucoseSecondRow: some View {
        GridRow(alignment: .center) {
            let currentBG = state.units == .mmolL ? state.currentBG.formattedAsMmolL : state.currentBG.description
            Text(
                currentBG
                    + " " +
                    state.units.rawValue
            )

            let targetDifference = state.units == .mmolL ? state.targetDifference.formattedAsMmolL : state.targetDifference
                .description
            let secondRow = targetDifference + " / " +
                (state.units == .mmolL ? state.isf.formattedAsMmolL : state.isf.description)
                .description + " ≈ " + self.insulinFormatter(state.targetDifferenceInsulin)

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
                Text(self.insulinFormatter(state.iob, .plain) + " U")
            }

            Text("Subtract IOB").foregroundColor(.secondary.opacity(colorScheme == .dark ? 0.65 : 0.8)).font(.footnote)

            HStack {
                Text(self.insulinFormatter(-1 * state.iob, .plain))
                Text("U").foregroundColor(.secondary)
            }.fontWeight(.bold)
                .gridColumnAlignment(.trailing)
        }
    }

    var calcCOBRow: some View {
        GridRow(alignment: .center) {
            let maxCobReached: Bool = state.wholeCob >= state.maxCOB
            Text(maxCobReached ? "Max COB:" : "COB:")
                .foregroundColor(maxCobReached ? Color.loopRed : .secondary)

            Text(
                state.wholeCob
                    .formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits)))
                    + " / " +
                    state.carbRatio.formatted()
                    + " ≈ " +
                    self.insulinFormatter(state.wholeCobInsulin)
            )
            .foregroundColor(.secondary)
            .gridColumnAlignment(.leading)

            HStack {
                Text(self.insulinFormatter(state.wholeCobInsulin))
                Text("U").foregroundColor(.secondary)
            }
            .fontWeight(.bold)
            .gridColumnAlignment(.trailing)
        }
    }

    var calcCOBFormulaRow: some View {
        GridRow(alignment: .center) {
            Text(
                state.wholeCob
                    .formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits))) +
                    String(localized: " g", comment: "grams")
            )

            Text("COB / Carb Ratio").foregroundColor(.secondary.opacity(colorScheme == .dark ? 0.65 : 0.8))
                .gridColumnAlignment(.leading).font(.caption)
        }
    }

    var calcDeltaRow: some View {
        GridRow(alignment: .center) {
            Text("Delta:").foregroundColor(.secondary)

            let deltaBG = state.units == .mmolL ? state.deltaBG.formattedAsMmolL : state.deltaBG.description
            let isf = state.units == .mmolL ? state.isf.formattedAsMmolL : state.isf.description

            let fifteenMinInsulinFormatted = self.insulinFormatter(state.fifteenMinInsulin)

            Text(
                deltaBG + " / " + isf + " ≈ " + fifteenMinInsulinFormatted
            )
            .foregroundColor(.secondary)
            .gridColumnAlignment(.leading)

            HStack {
                Text(fifteenMinInsulinFormatted)
                Text("U").foregroundColor(.secondary)
            }.fontWeight(.bold)
                .gridColumnAlignment(.trailing)
        }
    }

    var calcDeltaFormulaRow: some View {
        GridRow(alignment: .center) {
            let deltaBG = state.units == .mmolL ? state.deltaBG.formattedAsMmolL : state.deltaBG.description
            Text(
                deltaBG
                    + " " +
                    state.units.rawValue
            )

            Text("15 min Delta / ISF").font(.caption).foregroundColor(.secondary.opacity(colorScheme == .dark ? 0.65 : 0.8))
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
                Text("≈").foregroundColor(.secondary)
                Text(self.insulinFormatter(state.wholeCalc))
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

            Text(
                "\(state.currentBasal) × \(100 * state.sweetMealFactor)% ≈ \(state.superBolusInsulin) "
            )
            .foregroundColor(.secondary)
            .gridColumnAlignment(.leading)

            HStack {
                Text("+" + self.insulinFormatter(state.superBolusInsulin))
                    .foregroundStyle(Color.loopRed)
                Text("U").foregroundColor(.secondary)
            }.gridColumnAlignment(.trailing)
                .fontWeight(.bold)
        }
    }

    var calcSuperBolusFormulaRow: some View {
        GridRow(alignment: .center) {
            Text("\(state.currentBasal) U/hr")

            Text("Basal Rate × Super Bolus %").font(.caption)
                .foregroundColor(.secondary.opacity(colorScheme == .dark ? 0.65 : 0.8))
                .gridColumnAlignment(.leading)
                .gridCellColumns(2).padding(.top, 5)
        }
    }

    var calcResultRow: some View {
        GridRow(alignment: .center) {
            Text("Factors").foregroundColor(.secondary)

            HStack {
                Text(state.useSuperBolus ? "(" : "")
                    .foregroundColor(.loopRed)

                    + Text(self.insulinFormatter(state.wholeCalc))
                    .foregroundColor(state.wholeCalc < 0 ? Color.loopRed : Color.secondary)

                    + Text(" × ")

                    + Text((100 * state.fraction).formatted() + "%")

                    // if fatty meal is chosen
                    + Text(state.useFattyMealCorrectionFactor ? " × " : "")

                    + Text(state.useFattyMealCorrectionFactor ? (100 * state.fattyMealFactor).formatted() + "%" : "")
                    .foregroundColor(.orange)
                    // endif fatty meal is chosen

                    // if superbolus is chosen
                    + Text(state.useSuperBolus ? ")" : "")
                    .foregroundColor(.loopRed)

                    + Text(state.useSuperBolus ? " + " : "")

                    + Text(state.useSuperBolus ? self.insulinFormatter(state.superBolusInsulin) : "")
                    .foregroundColor(.loopRed)
                    // endif superbolus is chosen

                    + Text(" ≈ ")
            }
            .gridColumnAlignment(.leading)
            .foregroundColor(.secondary)

            HStack {
                Text(self.insulinFormatter(state.factoredInsulin))
                    .fontWeight(.bold)
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
                    Text("Full Bolus x Rec. Bolus % x Fatty Meal %")
                        .foregroundColor(.secondary.opacity(colorScheme == .dark ? 0.65 : 0.8))
                }
                .font(.caption)
                .gridCellAnchor(.center)
                .gridCellColumns(3)
            } else if state.useSuperBolus {
                Group {
                    Text("(Full Bolus x Rec. Bolus %) + Super Bolus")
                        .foregroundColor(.secondary.opacity(colorScheme == .dark ? 0.65 : 0.8))
                }
                .font(.caption)
                .gridCellAnchor(.center)
                .gridCellColumns(3)
            } else {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                Group {
                    Text("Full Bolus x Rec. Bolus %")
                        .foregroundColor(.secondary.opacity(colorScheme == .dark ? 0.65 : 0.8))
                }
                .font(.caption)
                .padding(.top, 5)
                .gridCellAnchor(.leading)
                .gridCellColumns(2)
            }
        }
    }

    var limitsRow: some View {
        GridRow(alignment: .top) {
            Text("Limits").foregroundColor(.secondary)

            VStack(alignment: .leading) {
                let iobAvailable: Decimal = state.maxIOB - state.iob
                let isLoopStale = state.lastLoopDate == nil ||
                    Date().timeIntervalSince(state.lastLoopDate!) > 15 * 60

                if isLoopStale {
                    Text("Last loop was > 15 mins ago.")
                } else if state.factoredInsulin < 0 {
                    Text("No insulin recommended.")
                } else if state.currentBG < 54 {
                    Text("Glucose is very low.")
                } else if state.minPredBG < 54 {
                    Text("Glucose forecast is very low.")
                } else if state.maxBolus <= iobAvailable && state.factoredInsulin > state.maxBolus {
                    Text("Max Bolus = \(insulinFormatter(state.maxBolus)) U")
                } else {
                    if state.factoredInsulin > iobAvailable {
                        let iobFormatted = state.iob < 0 ? "(" + insulinFormatter(state.iob) + ")" : insulinFormatter(state.iob)
                        Text("Available IOB = \(insulinFormatter(iobAvailable)) U")
                        Text("\(insulinFormatter(state.maxIOB)) - \(iobFormatted)")
                            .foregroundColor(.secondary)
                        Text("Max IOB - Current IOB")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if state.insulinCalculated > 0 {
                        Text("Rounded for pump.")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .foregroundColor(Color.loopRed)

            HStack {
                Text(insulinFormatter(state.insulinCalculated))
                    .foregroundColor(state.insulinCalculated > 0 ? Color.insulin : .primary)
                Text("U").foregroundColor(.secondary)
            }
            .fontWeight(.bold)
            .gridColumnAlignment(.trailing)
        }
    }

    private func insulinFormatter(_ value: Decimal, _ roundingMode: NSDecimalNumber.RoundingMode = .down) -> String {
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
        var height: CGFloat

        init(_ height: CGFloat = 1) {
            self.height = height
        }

        var body: some View {
            Rectangle()
                .frame(height: height)
                .foregroundColor(.gray.opacity(0.65))
                .padding(.vertical)
        }
    }
}
