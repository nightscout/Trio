import SwiftUI

struct QuickBolusInfoView: View {
    @Binding var isPresented: Bool

    @State private var detent = PresentationDetent.medium

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(String(
                    localized: "Quick Bolus looks at your manual boluses from the past 90 days and suggests the amounts you most commonly take at this time of day.\n\nIt gives more weight to boluses from similar times of day, and treats weekdays and weekends separately. Older entries gradually count less.\n\nTap a suggestion to select it, then slide to confirm. Your normal Face ID or Touch ID approval always applies.",
                    comment: "Info sheet body explaining how quick bolus scoring works"
                ))
                    .padding()
            }
            .navigationTitle(String(
                localized: "About Quick Bolus",
                comment: "Info sheet title for quick bolus feature"
            ))
            .navigationBarTitleDisplayMode(.inline)

            Button {
                isPresented = false
            } label: {
                Text("Got it!", comment: "Dismiss button for Quick Bolus info sheet")
                    .bold()
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .center)
            }
            .buttonStyle(.bordered)
            .padding([.horizontal, .bottom])
            .padding(.top, 4)
        }
        .presentationDetents([.medium], selection: $detent)
    }
}
