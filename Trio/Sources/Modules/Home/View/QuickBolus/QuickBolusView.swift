import SwiftUI

struct QuickBolusView: View {
    let suggestions: [Decimal]
    let onEnact: (Decimal) async -> Bool
    @Binding var isPresented: Bool

    @State private var selectedAmount: Decimal?
    @State private var showInfo = false
    @State private var isEnacting = false
    @State private var showAuthFailedAlert = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                pillRow
                    .padding(.top, 4)

                Text(
                    "Your most-used bolus amounts at similar times on similar days. Tap one to pick it.",
                    comment: "Subtitle of the quick bolus pill row"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .padding(.horizontal)
            }
            .frame(maxWidth: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 10) {
                SlideToConfirmView(
                    label: String(localized: "Slide to Enact Bolus", comment: "Slide to confirm label for quick bolus"),
                    isEnabled: selectedAmount != nil && !isEnacting
                ) {
                    guard let amount = selectedAmount, !isEnacting else { return }
                    isEnacting = true
                    Task {
                        let success = await onEnact(amount)
                        await MainActor.run {
                            if success {
                                isPresented = false
                            } else {
                                isEnacting = false
                                showAuthFailedAlert = true
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 6)
                .padding(.bottom, 8)
            }
            .navigationTitle(String(localized: "Quick Bolus", comment: "Title of the quick bolus sheet"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Quick Bolus", comment: "Title of the quick bolus sheet")
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
                QuickBolusInfoView(isPresented: $showInfo)
            }
            .alert(
                String(localized: "Could not authenticate", comment: "Alert title when biometric auth fails for quick bolus"),
                isPresented: $showAuthFailedAlert
            ) {
                Button(String(localized: "OK"), role: .cancel) {}
            } message: {
                Text(String(
                    localized: "Face ID or Touch ID did not succeed. The bolus was not enacted.",
                    comment: "Alert body when biometric auth fails for quick bolus"
                ))
            }
        }
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
    }

    private var displayedSuggestions: [Decimal] {
        Array(suggestions.prefix(3).sorted())
    }

    private var pillRow: some View {
        HStack(spacing: 16) {
            ForEach(displayedSuggestions, id: \.self) { amount in
                bolusAmountPill(amount)
                    .frame(maxWidth: displayedSuggestions.count < 3 ? 160 : .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
    }

    private func bolusAmountPill(_ amount: Decimal) -> some View {
        let isSelected = selectedAmount == amount
        let formatted = Formatter.bolusFormatter.string(from: amount as NSDecimalNumber) ?? amount.description

        return Button {
            selectedAmount = amount
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(formatted)
                    .font(.title2.bold())
                Text("U")
                    .font(.title2)
                    .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.accentColor : Color(.secondarySystemFill))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2.5)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}
