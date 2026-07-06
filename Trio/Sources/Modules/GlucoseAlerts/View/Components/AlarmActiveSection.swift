import SwiftUI

struct AlarmActiveSection: View {
    @Binding var activeOption: ActiveOption
    /// Subset of `ActiveOption` cases the picker is allowed to offer.
    /// Defaults to all cases when omitted.
    var allowed: [ActiveOption] = ActiveOption.allCases

    var body: some View {
        Section(
            header: Text("Active During"),
            footer: Text(
                "Day and Night windows are configured globally on the Alarms screen."
            )
        ) {
            AlarmEnumMenuPicker(
                title: String(localized: "Active"),
                selection: $activeOption,
                allowed: allowed
            )
        }.listRowBackground(Color.chart)
    }
}
