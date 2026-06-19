import SwiftUI

struct AlarmActiveSection: View {
    @Binding var activeOption: ActiveOption

    var body: some View {
        Section(
            header: Text("Active During"),
            footer: Text(
                "Day and Night windows are configured globally on the Alarms screen."
            )
        ) {
            AlarmEnumMenuPicker(title: String(localized: "Active"), selection: $activeOption)
        }.listRowBackground(Color.chart)
    }
}
