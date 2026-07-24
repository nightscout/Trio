import SlideButton
import SwiftUI

struct QuickPickTreatmentsView: View {
    let bolusSuggestions: [Decimal]
    let carbSuggestions: [Decimal]
    let onEnact: (_ bolusAmount: Decimal?, _ carbAmount: Decimal?) async -> Home.QuickPickTreatmentOutcome
    @Binding var isPresented: Bool

    @State private var selectedBolusAmount: Decimal?
    @State private var selectedCarbAmount: Decimal?
    @State private var showInfo = false
    @State private var isEnacting = false
    @State private var enactAlert: EnactAlert?

    private struct EnactAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        /// Whether the sheet should close once the user acknowledges this alert. False when the user can
        /// still retry the pick (e.g. nothing was saved), true when part or all of it already went through.
        let dismissesSheet: Bool
    }

    var body: some View {
        let titleText = String(localized: "Quick-Pick Treatments", comment: "Title of the quick-pick treatments sheet")
        NavigationStack {
            ZStack {
                VStack(alignment: .leading) {
                    if !displayedCarbSuggestions.isEmpty {
                        pillRow(
                            amounts: displayedCarbSuggestions,
                            selected: selectedCarbAmount,
                            accentColor: Color.orange,
                            formatter: Formatter.integerFormatter,
                            unit: carbUnitLabel,
                            select: toggleCarbSelection
                        )
                        .padding(.top)
                    }

                    if !displayedBolusSuggestions.isEmpty {
                        pillRow(
                            amounts: displayedBolusSuggestions,
                            selected: selectedBolusAmount,
                            accentColor: Color.accentColor,
                            formatter: Formatter.bolusFormatter,
                            unit: bolusUnitLabel,
                            select: toggleBolusSelection
                        )
                        .padding(.top, displayedCarbSuggestions.isEmpty ? 0 : 12)
                    }

                    Text(
                        "Your most-used amounts at similar times on similar days. Tap a bolus, a carb amount, or both.",
                        comment: "Subtitle of the quick-pick treatments pill rows"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .padding()

                    Spacer()

                    slideToConfirmButton
                }
                .padding(.horizontal)
                .frame(maxWidth: .infinity)
                .blur(radius: isEnacting ? 5 : 0)

                if isEnacting {
                    CustomProgressView(text: progressText.displayName)
                }
            }
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(titleText)
                        .font(.title3.bold())
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showInfo = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                }
            }
            .sheet(isPresented: $showInfo) {
                QuickPickTreatmentsInfoView(isPresented: $showInfo)
            }
            .alert(
                enactAlert?.title ?? "",
                isPresented: Binding(
                    get: { enactAlert != nil },
                    set: { isPresented in if !isPresented { enactAlert = nil } }
                ),
                presenting: enactAlert
            ) { alert in
                Button(String(localized: "Got it!"), role: .cancel) {
                    if alert.dismissesSheet {
                        isPresented = false
                    }
                }
            } message: { alert in
                Text(alert.message)
            }
        }
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isEnacting || enactAlert != nil)
    }

    private var slideToConfirmButton: some View {
        SlideButton(
            styling: .init(indicatorSystemName: "chevron.right.2", textAlignment: .globalCenter),
            action: { await enact() },
            label: { Text(slideToConfirmLabel) }
        )
        .disabled(selectedBolusAmount == nil && selectedCarbAmount == nil)
        .padding(.horizontal)
    }

    private var displayedBolusSuggestions: [Decimal] { Self.displayedSuggestions(from: bolusSuggestions, limit: 3) }
    private var displayedCarbSuggestions: [Decimal] { Self.displayedSuggestions(from: carbSuggestions, limit: 3) }

    /// Grows the sheet to fit however many pill rows are actually shown, rather than assuming both rows render.
    private var sheetHeight: CGFloat {
        let rowCount = (displayedBolusSuggestions.isEmpty ? 0 : 1) + (displayedCarbSuggestions.isEmpty ? 0 : 1)
        return rowCount >= 2 ? 380 : 320
    }

    private var bolusUnitLabel: String {
        String(localized: "U", comment: "Insulin unit abbreviation shown next to a quick-pick bolus amount")
    }

    private var carbUnitLabel: String {
        String(localized: "g", comment: "Abbreviation for grams shown next to a quick-pick carb amount")
    }

    private func toggleBolusSelection(_ amount: Decimal) {
        selectedBolusAmount = selectedBolusAmount == amount ? nil : amount
    }

    private func toggleCarbSelection(_ amount: Decimal) {
        selectedCarbAmount = selectedCarbAmount == amount ? nil : amount
    }

    private static func displayedSuggestions(from suggestions: [Decimal], limit: Int) -> [Decimal] {
        var seen = Set<Decimal>()
        return suggestions.prefix(limit).filter { seen.insert($0).inserted }.sorted()
    }

    private var slideToConfirmLabel: String {
        switch (selectedBolusAmount != nil, selectedCarbAmount != nil) {
        case (true, true):
            return String(
                localized: "Slide to Log and Enact",
                comment: "Slide to confirm label when both a bolus and carbs are picked"
            )
        case (true, false):
            return String(localized: "Slide to Enact", comment: "Slide to confirm label when only a bolus is picked")
        case (false, true):
            return String(localized: "Slide to Log", comment: "Slide to confirm label when only carbs are picked")
        case (false, false):
            return String(localized: "Slide to Confirm", comment: "Slide to confirm label when nothing is picked yet")
        }
    }

    /// Matches `TreatmentsRootView.progressText`, so the same "Updating IOB/COB" wording is used while a
    /// Quick-Pick Treatment is being enacted.
    private var progressText: ProgressText {
        switch (selectedBolusAmount != nil, selectedCarbAmount != nil) {
        case (true, true):
            return .updatingIOBandCOB
        case (false, true):
            return .updatingCOB
        case (true, false):
            return .updatingIOB
        default:
            return .updatingTreatments
        }
    }

    private func enact() async {
        guard selectedBolusAmount != nil || selectedCarbAmount != nil, !isEnacting else { return }
        isEnacting = true
        let outcome = await onEnact(selectedBolusAmount, selectedCarbAmount)
        await MainActor.run {
            handle(outcome)
        }
    }

    private func handle(_ outcome: Home.QuickPickTreatmentOutcome) {
        isEnacting = false

        switch (outcome.carbsResult, outcome.bolusResult) {
        case (nil, nil),
             (nil, .succeeded),
             (.succeeded, nil),
             (.succeeded, .succeeded):
            isPresented = false

        case (.succeeded, .failed):
            enactAlert = EnactAlert(
                title: String(localized: "Bolus Not Enacted", comment: "Alert title when carbs saved but the bolus failed"),
                message: String(
                    localized: "Carbs were logged, but the bolus could not be authenticated and was not enacted.",
                    comment: "Alert body when carbs saved but the bolus failed"
                ),
                dismissesSheet: true
            )

        case (.failed, .succeeded):
            enactAlert = EnactAlert(
                title: String(
                    localized: "Carbs Not Logged",
                    comment: "Alert title when the bolus was enacted but carbs failed to save"
                ),
                message: String(
                    localized: "The bolus was enacted, but the carbs could not be logged. Please log them manually.",
                    comment: "Alert body when the bolus was enacted but carbs failed to save"
                ),
                dismissesSheet: true
            )

        case (.failed, .failed):
            enactAlert = EnactAlert(
                title: String(localized: "Nothing Was Saved", comment: "Alert title when both carbs and bolus failed"),
                message: String(
                    localized: "Neither the carbs nor the bolus could be saved. Please try again.",
                    comment: "Alert body when both carbs and bolus failed"
                ),
                dismissesSheet: false
            )

        case (nil, .failed):
            enactAlert = EnactAlert(
                title: String(
                    localized: "Could Not Authenticate",
                    comment: "Alert title when biometric auth fails for a quick-pick bolus"
                ),
                message: String(
                    localized: "Face ID or Touch ID did not succeed. The bolus was not enacted.",
                    comment: "Alert body when biometric auth fails for a quick-pick bolus"
                ),
                dismissesSheet: false
            )

        case (.failed, nil):
            enactAlert = EnactAlert(
                title: String(localized: "Carbs Not Logged", comment: "Alert title when a carbs-only quick pick fails to save"),
                message: String(
                    localized: "The carbs could not be logged. Please try again.",
                    comment: "Alert body when a carbs-only quick pick fails to save"
                ),
                dismissesSheet: false
            )
        }
    }

    private func pillRow(
        amounts: [Decimal],
        selected: Decimal?,
        accentColor: Color,
        formatter: NumberFormatter,
        unit: String,
        select: @escaping (Decimal) -> Void
    ) -> some View {
        let isCompact = amounts.count < 2
        return HStack(spacing: 16) {
            if isCompact { Spacer() }

            ForEach(amounts, id: \.self) { amount in
                amountPill(
                    amount: amount,
                    isSelected: selected == amount,
                    accentColor: accentColor,
                    formatter: formatter,
                    unit: unit,
                    action: { select(amount) }
                )
                .frame(maxWidth: isCompact ? 160 : .infinity)
            }

            if isCompact { Spacer() }
        }
        .padding(.horizontal)
    }

    private func amountPill(
        amount: Decimal,
        isSelected: Bool,
        accentColor: Color,
        formatter: NumberFormatter,
        unit: String,
        action: @escaping () -> Void
    ) -> some View {
        let formatted = formatter.string(from: amount as NSDecimalNumber) ?? amount.description

        return Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(formatted)
                    .font(.title2.bold())
                Text(unit)
                    .font(.title2)
                    .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.vertical, 12)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(isSelected ? accentColor : Color(.secondarySystemFill))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(accentColor, lineWidth: 2.5)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}
