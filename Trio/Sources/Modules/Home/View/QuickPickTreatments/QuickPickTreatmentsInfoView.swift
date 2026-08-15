import SwiftUI

struct QuickPickTreatmentsInfoView: View {
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(String(
                    localized: "Quick-Pick Treatments looks at your manual boluses and carb entries from the past 90 days and suggests the amounts you most commonly enter at this time of day.\n\nIt gives more weight to entries from similar times of day, and treats weekdays and weekends separately. Older entries gradually count less.\n\nTap a bolus amount, a carb amount, or both, then slide to confirm.\n\nFor calculator or recommendations, use the Treatments View.",
                    comment: "Info sheet body explaining how quick-pick treatments scoring works"
                ))
                    .padding()
            }
            .navigationTitle(String(
                localized: "About Quick-Pick Treatments",
                comment: "Info sheet title for quick-pick treatments feature"
            ))
            .navigationBarTitleDisplayMode(.inline)

            Button {
                isPresented = false
            } label: {
                Text("Got it!", comment: "Dismiss button for Quick-Pick Treatments info sheet")
                    .bold()
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .center)
            }
            .buttonStyle(.bordered)
            .padding([.horizontal, .bottom])
            .padding(.top, 4)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
