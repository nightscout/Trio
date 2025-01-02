import SwiftUI

struct TempTargetHelpView: View {
    var state: Adjustments.StateModel
    var helpSheetDetent: Binding<PresentationDetent>

    var body: some View {
        NavigationStack {
            List {
                VStack(alignment: .leading, spacing: 10) {
                    Text(
                        "A Temporary Target replaces the current Target Glucose specified in Therapy settings."
                    )
                    Text(
                        "Depending on your Target Behavior settings (see Settings > the Algorithm > Target Behavior), these temporary glucose targets can also raise Insulin Sensitivity for high targets or lower sensitivity for low targets."
                    )
                    Text(
                        "Furthermore, you could adjust that sensitivity change independently from the Half Basal Exercise Target specified in Algorithm > Target Behavior settings by deliberatly setting a customized Insulin Percentage for a Temp Target."
                    )
                    Text(
                        "A pre-condition to have Temp Targets adjust Sensitivity is that the respective Target Behavior settings High Temp Target Raises Sensitivity or Low Temp Target Lowers Sensitivity are set to enabled."
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
