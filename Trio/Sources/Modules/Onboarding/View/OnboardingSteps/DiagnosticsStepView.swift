import SwiftUI

struct DiagnosticsStepView: View {
    @Bindable var state: Onboarding.StateModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("If you prefer not to share this anonymized data, you can opt-out of data sharing.")
                .font(.headline)
                .padding(.horizontal)
                .multilineTextAlignment(.leading)

            ForEach(DiagnostisSharingOption.allCases, id: \.self) { option in
                Button(action: {
                    state.diagnosticsSharingOption = option
                }) {
                    HStack {
                        Image(systemName: state.diagnosticsSharingOption == option ? "largecircle.fill.circle" : "circle")
                            .foregroundColor(state.diagnosticsSharingOption == option ? .accentColor : .secondary)
                            .imageScale(.large)

                        Text(option.displayName)
                            .foregroundColor(.primary)

                        Spacer()
                    }
                    .padding()
                    .background(Color.chart.opacity(0.65))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Why does Trio collect this data?").bold()
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        "•  App diagnostic insights help us enhance app stability, ensure safety for all users, and enable us to quickly identify and resolve critical issues."
                    )
                    Text("•  Trio collects the app's state on crash, device, iOS and general system info, and a stack trace.")
                    Text(
                        "•  Trio does not collect any health related data, e.g. glucose readings, insulin rates or doses, meal data, setting values, or similar."
                    )
                    Text(
                        "•  Trio does not track any usage metrics or any other personal data about users other than the used iPhone model and iOS version."
                    )
                }
                Text(
                    "Diagnostics are sent to a Google Firebase Crashlytics project, which is securely maintained and accessed only by the Trio team."
                )
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal)
            .font(.footnote)
            .foregroundStyle(Color.secondary)
        }
    }
}
