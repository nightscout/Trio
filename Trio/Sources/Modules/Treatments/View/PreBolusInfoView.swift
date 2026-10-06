import SwiftUI

struct PreBolusInfoView: View {
    var state: Treatments.StateModel

    @Binding var isPresented: Bool

    @State private var detent = PresentationDetent.large

    @ScaledMetric(relativeTo: .footnote) private var conditionColumnWidth: CGFloat = 110

    private var recommendation: PreBolusRecommendation { state.recommendedPreBolus }

    var body: some View {
        NavigationStack {
            VStack(alignment: .center) {
                List {
                    Section("Your Numbers") { inputsCard }
                    Section("How It Was Derived") { derivationCard }
                    Section {
                        NavigationLink {
                            rulesView
                        } label: {
                            Label(String(localized: "The Rules"), systemImage: "list.bullet.rectangle")
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .listStyle(InsetGroupedListStyle())

                VStack(alignment: .center, spacing: 10) {
                    resultCard

                    Button {
                        isPresented = false
                    } label: {
                        Text("Got it!").bold()
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.bordered)
                }
                .padding([.horizontal, .bottom])
            }
            .navigationBarTitle(String(localized: "Pre-Bolus Details"), displayMode: .inline)
            .presentationDetents([.fraction(0.9), .large], selection: $detent)
        }
    }

    // MARK: - Cards

    private var inputsCard: some View {
        Group {
            labelledRow(String(localized: "Glucose"), state.currentBG.formatted(for: state.units), state.units.rawValue)
            labelledRow(String(localized: "Target"), state.target.formatted(for: state.units), state.units.rawValue)
            labelledRow(
                String(localized: "Trend (15 min)"),
                state.deltaBG.formatted(for: state.units),
                state.units.rawValue
            )
            labelledRow(
                String(localized: "Carbs"),
                Int(state.carbs).description,
                String(localized: "g", comment: "Unit for grams of carbohydrates")
            )

            if state.fat > 0 || state.protein > 0 {
                labelledRow(
                    String(localized: "Fat"),
                    Int(state.fat).description,
                    String(localized: "g", comment: "Unit for grams of fat")
                )
                labelledRow(
                    String(localized: "Protein"),
                    Int(state.protein).description,
                    String(localized: "g", comment: "Unit for grams of protein")
                )
            }
        }
    }

    private var derivationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let gateReason = recommendation.gateReason {
                derivationStep(
                    title: String(localized: "Safety rule"),
                    detail: gateReason,
                    value: minutesString(0),
                    valueColor: recommendation.isBelowLowThreshold ? .red : .orange
                )
            } else {
                derivationStep(
                    title: String(localized: "From the meal"),
                    detail: recommendation.baseReason,
                    value: minutesString(recommendation.mealBase),
                    valueColor: .primary
                )

                if let insulinAdjustmentReason = recommendation.insulinAdjustmentReason {
                    Divider()
                    derivationStep(
                        title: String(localized: "From the insulin"),
                        detail: insulinAdjustmentReason,
                        value: signedMinutesString(recommendation.insulinAdjustment),
                        valueColor: .accentColor
                    )
                }

                if let adjustmentReason = recommendation.adjustmentReason {
                    Divider()
                    derivationStep(
                        title: String(localized: "From glucose"),
                        detail: adjustmentReason,
                        value: signedMinutesString(recommendation.adjustment),
                        valueColor: .accentColor
                    )
                }

                if recommendation.uncappedMinutes != recommendation.minutes {
                    Divider()
                    derivationStep(
                        title: String(localized: "Capped"),
                        detail: String(
                            localized: "Past \(PreBolusRecommendation.Config.maxMinutes) minutes a lead time just builds a dip before the meal."
                        ),
                        value: minutesString(recommendation.minutes),
                        valueColor: .primary
                    )
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Pushed sub-page holding the full rule table, so the main sheet stays focused on this meal.
    private var rulesView: some View {
        List {
            Section { rulesCard }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationBarTitle(String(localized: "The Rules"), displayMode: .inline)
    }

    /// The lookup table the rules were written from, so the recommendation can be sanity-checked
    /// against it.
    private var rulesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ruleHeader(String(localized: "1. Safety rules. These win outright."))
            ruleRow(
                String(localized: "Below \(PreBolusRecommendation.Config.lowThreshold.formatted(for: state.units))"),
                String(localized: "Treat the low first, no pre-bolus")
            )
            ruleRow(String(localized: "No recent glucose"), String(localized: "0 min, bolus with the first bite"))
            ruleRow(String(localized: "Falling"), String(localized: "0 min, bolus with the first bite"))
            ruleRow(String(localized: "Below target"), String(localized: "0 min, bolus with the first bite"))

            Divider()

            ruleHeader(String(localized: "2. A base lead: how fast do the carbs land?"))
            ruleRow(
                String(localized: "Fast carbs"),
                String(localized: "20 min. Carbs only, no fat or protein: juice, cereal, fruit, white bread")
            )
            ruleRow(
                String(localized: "Everything else"),
                String(localized: "15 min. Sandwich, rice, pasta, pizza, a normal plate")
            )
            ruleFootnote(
                String(
                    localized: "Fat does not shorten the lead. This bolus covers the carbs you entered; fat and protein are dosed later as carb equivalents, so counting their delay here would under-lead the carbs."
                )
            )

            Divider()

            ruleHeader(String(localized: "3. How fast is your insulin?"))
            ruleRow(
                String(localized: "Rapid-acting"),
                String(localized: "The base stands. Novolog, Humalog, Apidra.")
            )
            ruleRow(
                String(localized: "Ultra-rapid"),
                String(localized: "5 min shorter. Fiasp, Lyumjev.")
            )

            Divider()

            ruleHeader(String(localized: "4. Adjust for glucose"))
            ruleRow(String(localized: "At target, steady"), String(localized: "No change"))
            ruleRow(String(localized: "Rising"), String(localized: "+5 min"))
            ruleRow(String(localized: "Above target"), String(localized: "+5 min"))
            ruleRow(String(localized: "Well above target"), String(localized: "+10 min"))
            ruleRow(
                String(localized: "Ceiling"),
                String(localized: "Never more than \(PreBolusRecommendation.Config.maxMinutes) min")
            )
        }
        .padding(.vertical, 4)
    }

    private var resultCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.accentColor.opacity(0.1))

            HStack {
                Text("Recommended Pre-Bolus").font(.headline)
                    .fixedSize(horizontal: true, vertical: true)

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(recommendation.minutes.description)
                        .font(.system(.title3, weight: .bold))
                        .foregroundStyle(recommendation.minutes > 0 ? Color.accentColor : .primary)
                    Text("min")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Row builders

    private func labelledRow(_ label: String, _ value: String, _ unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).fontWeight(.semibold)
                Text(unit).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func derivationStep(title: String, detail: String, value: String, valueColor: Color) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).fontWeight(.semibold)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Text(value)
                .font(.system(.headline, weight: .bold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .layoutPriority(5)
        }
    }

    private func ruleHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textCase(nil)
    }

    /// A full-width note under a rules group: caption styling and no indent, so it reads as a
    /// footnote rather than a row missing its key.
    private func ruleFootnote(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ruleRow(_ condition: String, _ outcome: String) -> some View {
        HStack(alignment: .top) {
            Text(condition)
                .font(.footnote)
                .fontWeight(.semibold)
                .frame(width: conditionColumnWidth, alignment: .leading)
            Text(outcome)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func minutesString(_ minutes: Int) -> String {
        "\(minutes) " + String(localized: "min")
    }

    private func signedMinutesString(_ minutes: Int) -> String {
        (minutes > 0 ? "+" : "") + minutesString(minutes)
    }
}
