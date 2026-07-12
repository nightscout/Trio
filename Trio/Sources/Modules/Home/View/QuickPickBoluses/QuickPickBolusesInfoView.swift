import SwiftUI

struct QuickPickBolusesInfoView: View {
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(String(
                    localized: "Quick-Pick Boluses looks at your manual boluses from the past 90 days and suggests the amounts you most commonly enact at this time of day.\n\nIt gives more weight to boluses from similar times of day, and treats weekdays and weekends separately. Older entries gradually count less.\n\nTap a suggestion to select it, then slide to confirm. Your normal Face ID or Touch ID approval always applies.",
                    comment: "Info sheet body explaining how quick-pick boluses scoring works"
                ))
                    .padding()
            }
            .navigationTitle(String(
                localized: "About Quick-Pick Boluses",
                comment: "Info sheet title for quick-pick boluses feature"
            ))
            .navigationBarTitleDisplayMode(.inline)

            Button {
                isPresented = false
            } label: {
                Text("Got it!", comment: "Dismiss button for Quick-Pick Boluses info sheet")
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
