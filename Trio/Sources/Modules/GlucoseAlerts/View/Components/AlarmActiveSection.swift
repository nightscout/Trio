import SwiftUI

struct AlarmActiveSection: View {
    @Binding var alarm: GlucoseAlert

    var body: some View {
        Section(
            header: Text("Active During"),
            footer: Text(
                "Day and Night windows are configured globally on the Alarms screen."
            )
        ) {
            AlarmEnumMenuPicker(title: String(localized: "Active"), selection: $alarm.activeOption)
        }.listRowBackground(Color.chart)
    }
}
