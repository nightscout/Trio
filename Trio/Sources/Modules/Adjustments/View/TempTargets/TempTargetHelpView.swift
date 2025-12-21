import SwiftUI

struct TempTargetHelpView: View {
    var state: Adjustments.StateModel
    var helpSheetDetent: Binding<PresentationDetent>

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(
                            "A Temporary Target replaces the current Target Glucose specified in Therapy settings."
                        )
                        Text(
                            "Depending on your Target Behavior settings (see Settings > the Algorithm > Target Behavior), these temporary glucose targets can also raise Insulin Sensitivity for high targets or lower sensitivity for low targets."
                        )
                        Text(
                            "Furthermore, you could adjust that sensitivity change independently from the Half Basal Exercise Target specified in Algorithm > Target Behavior settings by deliberately setting a customized Insulin Percentage for a Temp Target."
                        )
                        Text(
                            "A pre-condition to have Temp Targets adjust Sensitivity is that the respective Target Behavior settings High Temp Target Raises Sensitivity or Low Temp Target Lowers Sensitivity are set to enabled."
                        )
                    }
                } header: {
                    Text("Overview")
                }
                .listRowBackground(Color.gray.opacity(0.1))

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(
                            "Sensitivity changes from Temp Targets have a built-in minimum of 15%. Even very high Temp Targets cannot reduce insulin delivery below 15% of normal."
                        )
                        Text(
                            "This 15% minimum is a safety limit taken from oref (OpenAPS reference design) and AndroidAPS. It helps prevent insulin delivery from dropping to unsafe levels."
                        )
                        Text(
                            "Important: Autosens Min and Autosens Max do not affect Temp Targets in the same way. Autosens Max limits how much insulin can be increased, but Autosens Min does not remove the 15% minimum when insulin is reduced."
                        )
                        Text(
                            "This difference exists because situations like exercise often need a much larger insulin reduction than Autosens would detect during a normal daily routine."
                        )
                    }
                } header: {
                    Text("Sensitivity Limits")
                }
                .listRowBackground(Color.gray.opacity(0.1))
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
