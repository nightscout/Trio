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
                label: { Text("Got it!").bold().frame(maxWidth: .infinity, minHeight: 30, alignment: .center) }
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

            let isf = state.units == .mmolL ? state.isf.formattedAsMmolL : state.isf.description
            Text(
                isf + " " + state.units
                    .rawValue + NSLocalizedString("/U", comment: "/Insulin unit")
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
                Text(
                    self.insulinFormatter(state.iob)
                )
            }

            Text("Subtract IOB").foregroundColor(.secondary.opacity(colorScheme == .dark ? 0.65 : 0.8)).font(.footnote)

            let iobFormatted = self.insulinFormatter(state.iob)
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
                    self.insulinFormatter(state.wholeCobInsulin)
            )
            .foregroundColor(.secondary)
            .gridColumnAlignment(.leading)

            HStack {
                Text(
                    self.insulinFormatter(state.wholeCobInsulin)
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

            Text("Added to Result").foregroundColor(.secondary.opacity(colorScheme == .dark ? 0.65 : 0.8)).font(.footnote)

            HStack {
                Text("+" + self.insulinFormatter(state.superBolusInsulin))
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

                    + Text(self.insulinFormatter(state.wholeCalc))
                    .foregroundColor(state.wholeCalc < 0 ? Color.loopRed : Color.primary)

                    // if superbolus is chosen
                    + Text(state.useSuperBolus ? ")" : "")
                    .foregroundColor(.loopRed)

                    + Text(state.useSuperBolus ? " + " : "")
                    .foregroundColor(.secondary)

                    + Text(state.useSuperBolus ? self.insulinFormatter(state.superBolusInsulin) : "")
                    .foregroundColor(.loopRed)
                    // endif superbolus is chosen

                    + Text(" ≈ ")
                    .foregroundColor(.secondary)
            }
            .gridColumnAlignment(.leading)

            HStack {
                Text(self.insulinFormatter(state.insulinCalculated))
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

    private func insulinFormatter(_ value: Decimal) -> String {
        let toRound = NSDecimalNumber(decimal: value).doubleValue
        let roundedValue = Decimal(floor(100 * toRound) / 100)

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.locale = Locale.current // Uses the user's locale

        return formatter.string(from: roundedValue as NSNumber) ?? String(format: "%.2f", toRound)
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
