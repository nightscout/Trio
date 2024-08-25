import SwiftUI

struct NightscoutImportResultView: View {
    @ObservedObject var state: NightscoutConfig.StateModel

    @State private var shouldDisplayHint: Bool = false
    @State var hintDetent = PresentationDetent.large
    @State var selectedVerboseHint: String?
    @State var hintLabel: String?
    @State private var decimalPlaceholder: Decimal = 0.0
    @State private var booleanPlaceholder: Bool = false

    @Environment(\.colorScheme) var colorScheme
    var color: LinearGradient {
        colorScheme == .dark ? LinearGradient(
            gradient: Gradient(colors: [
                Color.bgDarkBlue,
                Color.bgDarkerDarkBlue
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
            :
            LinearGradient(
                gradient: Gradient(colors: [Color.gray.opacity(0.1)]),
                startPoint: .top,
                endPoint: .bottom
            )
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                Text(
                    "Trio has successfully imported your default Nightscout profile and applied it as therapy settings. This has replaced your previous therapy settings."
                )

                Text("Please review the following settings")
                
                Navigation

//                Text("• Basal Rates")
//                Text("• Insulin Sensitivities")
//                Text("• Carb Ratios")
//                Text("• Glucose Targets")
//                Text("• Duration of Insulin Action (DIA)")

                Spacer()

                Button {
                    Task {
                        await state.importSettings()
                    }
                } label: {
                    Text("Start Import")
                        .font(.title3)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.url.isEmpty || state.connecting || state.backfilling)

                Spacer()
            }.padding()
                .toolbar(content: {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: { state.isProfileImportPresented = false }, label: {
                            Text("Cancel")
                        })
                    }
                })
                .navigationTitle("Nightscout Import")
                .navigationBarTitleDisplayMode(.automatic)
                .scrollContentBackground(.hidden).background(color)
        }
    }
}
