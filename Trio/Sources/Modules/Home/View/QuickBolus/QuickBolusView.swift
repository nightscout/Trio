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
            VStack(spacing: 20) {
                pillRow
                    .padding(.top, 8)

                Text(
                    "Your most-used bolus amounts at similar times on similar days. Tap one to pick it.",
                    comment: "Subtitle of the quick bolus pill row"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            }
            .frame(maxWidth: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
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
                .padding(.vertical, 12)
            }
            .navigationTitle(String(localized: "Quick Bolus", comment: "Title of the quick bolus sheet"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showInfo = true
                    } label: {
                        Image(systemName: "info.circle")
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
    }

    private var displayedSuggestions: [Decimal] {
        Array(suggestions.prefix(3).sorted())
    }

    private var pillRow: some View {
        HStack(spacing: 12) {
            ForEach(displayedSuggestions, id: \.self) { amount in
                bolusAmountPill(amount)
            }
        }
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
                    .font(.callout)
                    .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
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
