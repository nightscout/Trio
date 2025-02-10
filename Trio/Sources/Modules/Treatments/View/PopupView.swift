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
                        calcSuperBolusFormulaRow
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
            let secondRow = targetDifference + " ÷ " +
                (state.units == .mmolL ? state.isf.formattedAsMmolL : state.isf.description)
                .description + " ≈ " + self.insulinFormatter(state.targetDifferenceInsulin)

            Text(secondRow).foregroundColor(.secondary).gridColumnAlignment(.leading)

            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
        }
    }

    var calcGlucoseFormulaRow: some View {
        GridRow(alignment: .top) {
            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])

            Text("(Current - Target) ÷ ISF").foregroundColor(.secondary.opacity(colorScheme == .dark ? 0.65 : 0.8))
                .gridColumnAlignment(.leading)
                .gridCellColumns(2)
        }
        .font(.caption)
    }

    var calcIOBRow: some View {
        GridRow(alignment: .center) {
            HStack {
                Text("IOB:").foregroundColor(.secondary)
                Text(self.insulinFormatter(state.iob) + " U")
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
            // Left column using ZStack to overlay Max COB
            ZStack(alignment: .leading) {
                // Main COB content
                HStack {
                    Text("COB:").foregroundColor(.secondary)
                    Text(
                        state.wholeCob
                            .formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits))) +
                            NSLocalizedString(" g", comment: "grams")
                    ).foregroundColor(state.wholeCob >= state.maxCOB ? Color.loopRed : .primary)
                }

                // Max COB overlay positioned below
                if state.wholeCob >= state.maxCOB {
                    Text("Max COB")
                        .foregroundColor(Color.loopRed)
                        .font(.caption)
                        .offset(y: 16) // Adjust this value to position the text correctly
                }
            }
            .frame(height: 20) // Fixed height for main content only

            // Middle column
            Text(
                state.wholeCob
                    .formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits)))
                    + " ÷ " +
                    state.carbRatio.formatted()
                    + " ≈ " +
                    self.insulinFormatter(state.wholeCobInsulin)
            )
            .foregroundColor(.secondary)
            .gridColumnAlignment(.leading)

            // Right column
            HStack {
                Text(
                    self.insulinFormatter(state.wholeCobInsulin)
                )
                Text("U").foregroundColor(.secondary)
            }
            .fontWeight(.bold)
            .gridColumnAlignment(.trailing)
        }
    }

    var calcCOBFormulaRow: some View {
        GridRow(alignment: .center) {
            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])

            Text("COB ÷ Carb Ratio").foregroundColor(.secondary.opacity(colorScheme == .dark ? 0.65 : 0.8))
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
                deltaBG + " ÷ " + isf + " ≈ " + fifteenMinInsulinFormatted
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

            Text("15 min Delta ÷ ISF").font(.caption).foregroundColor(.secondary.opacity(colorScheme == .dark ? 0.65 : 0.8))
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
            Text("Result").fontWeight(.bold)

            HStack {
                Text(state.useSuperBolus ? "(" : "")
                    .foregroundColor(.loopRed)

                    + Text(self.insulinFormatter(state.wholeCalc))
                    .foregroundColor(state.wholeCalc < 0 ? Color.loopRed : Color.primary)

                    + Text(" × ")
                    .foregroundColor(.secondary)

                    + Text((100 * state.fraction).formatted() + "%")

                    // if fatty meal is chosen
                    + Text(state.useFattyMealCorrectionFactor ? " × " : "")
                    .foregroundColor(.secondary)

                    + Text(state.useFattyMealCorrectionFactor ? (100 * state.fattyMealFactor).formatted() + "%" : "")
                    .foregroundColor(.orange)
                    // endif fatty meal is chosen

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
                    .foregroundColor(state.insulinCalculated >= state.maxBolus ? Color.loopRed : Color.blue)
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
                    getFormulaText("Full Bolus x Fatty Meal % x Percentage", colorScheme: colorScheme) +
                        getCappedText(
                            insulinCalculated: state.insulinCalculated,
                            maxBolus: state.maxBolus,
                            maxIOB: state.maxIOB,
                            iob: state.iob
                        )
                }
                .font(.caption)
                .gridCellAnchor(.center)
                .gridCellColumns(3)
            } else if state.useSuperBolus {
                Group {
                    getFormulaText("(Full Bolus x Percentage) + Super Bolus", colorScheme: colorScheme) +
                        getCappedText(
                            insulinCalculated: state.insulinCalculated,
                            maxBolus: state.maxBolus,
                            maxIOB: state.maxIOB,
                            iob: state.iob
                        )
                }
                .font(.caption)
                .gridCellAnchor(.center)
                .gridCellColumns(3)
            } else {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                Group {
                    getFormulaText("Full Bolus x Percentage", colorScheme: colorScheme) +
                        getCappedText(
                            insulinCalculated: state.insulinCalculated,
                            maxBolus: state.maxBolus,
                            maxIOB: state.maxIOB,
                            iob: state.iob
                        )
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

extension View {
    // Function to generate the warning text for max bolus/IOB
    func getCappedText(insulinCalculated: Decimal, maxBolus: Decimal, maxIOB: Decimal, iob: Decimal) -> Text {
        let limitedByMaxBolus = insulinCalculated >= maxBolus && maxBolus < maxIOB - iob
        let limitedByMaxIOB = insulinCalculated >= maxIOB - iob
        return Text(
            limitedByMaxBolus ? " ≈ Max Bolus" :
                limitedByMaxIOB ? " ≈ Max IOB" : ""
        ).foregroundColor(Color.loopRed)
    }

    // Function to generate the formula text with opacity
    func getFormulaText(_ text: String, colorScheme: ColorScheme) -> Text {
        Text(text)
            .foregroundColor(.secondary.opacity(colorScheme == .dark ? 0.65 : 0.8))
    }
}
