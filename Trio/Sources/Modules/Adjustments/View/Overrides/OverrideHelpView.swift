import SwiftUI

struct OverrideHelpView: View {
    var state: Adjustments.StateModel
    var helpSheetDetent: Binding<PresentationDetent>

    var body: some View {
        NavigationStack {
            List {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(
                            "This feature can be used to override these therapy settings for a chosen length of time:"
                        )
                        .fixedSize(horizontal: false, vertical: true)
                        Text("• Basal Rate")
                        Text("• Insulin Sensitivity")
                        Text("• Carb Ratio")
                        Text("• Glucose Target")
                    }
                    Text(
                        "There are also options to override your Max SMB Minutes and Max UAM SMB Minutes, as well as to disable SMBs."
                    )
                    Text(
                        "Select \"Start Override\" to immediately start using the Override, or select \"Save as Preset\" to be able to easily start the Override at a later time."
                    )
                    Text(
                        "If an active override preset is edited, the changes will also apply to the currently running override. However, if you edit the currently running override directly, the preset stays unchanged."
                    )
                    Text(
                        "If using Dynamic ISF (without Sigmoid), overriding your ISF will only adjust the limits of the ISF the algorithm is allowed to set."
                    )
                    Text(
                        "If using Dynamic ISF (with Sigmoid), overriding your ISF will adjust the ISF used at your glucose target which extends to the ISF used at other glucose. Overriding your glucose target will change glucose level your ISF will be set to your profile ISF. Both of these can be combined in a single Override."
                    )
                }.listRowBackground(Color.gray.opacity(0.1))
            }
            .navigationBarTitle("Help", displayMode: .inline)

            Button { state.isHelpSheetPresented.toggle() }
            label: { Text("Got it!").bold().frame(maxWidth: .infinity, minHeight: 30, alignment: .center) }
                .buttonStyle(.bordered)
                .padding(.top)
        }

        .padding()
        .scrollContentBackground(.hidden)
        .presentationDetents(
            [.fraction(0.9), .large],
            selection: helpSheetDetent
        )
    }
}
