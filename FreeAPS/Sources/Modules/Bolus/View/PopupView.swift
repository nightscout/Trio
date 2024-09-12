import SwiftUI

struct PopupView: View {
    @StateObject var state: Bolus.StateModel
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

                Button { state.showInfo = false }
                label: { Text("Got it!").frame(maxWidth: .infinity, alignment: .center) }
                    .buttonStyle(.bordered)
                    .padding(.top)
            }
            .padding([.horizontal, .bottom])
            .font(.subheadline)
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
                (state.units == .mgdL ? state.isf : state.isf.asMmolL).formatted()
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

    private func insulinRounder(_ value: Decimal) -> Decimal {
        let toRound = NSDecimalNumber(decimal: value).doubleValue
        return Decimal(floor(100 * toRound) / 100)
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

// #Preview {
//    PopupView()
// }
