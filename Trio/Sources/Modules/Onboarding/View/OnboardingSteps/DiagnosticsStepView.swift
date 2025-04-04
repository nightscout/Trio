import SwiftUI

struct DiagnosticsStepView: View {
    @Bindable var state: Onboarding.StateModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("If you prefer not to share this anonymized data, you can opt-out of data sharing.")
                .font(.headline)

            ForEach(DiagnostisSharingOption.allCases, id: \.self) { option in
                Button(action: {
                    state.diagnostisSharingOption = option
                }) {
                    HStack {
                        Image(systemName: state.diagnostisSharingOption == option ? "largecircle.fill.circle" : "circle")
                            .foregroundColor(state.diagnostisSharingOption == option ? .accentColor : .secondary)
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
                    Text("•  Trio collects the App state on crash, device, iOS and general system info, and crash stack trace.")
                }
                Text(
                    "Trio diagnostic data is sent to a Google Firebase Crashlytics project, which is securely maintained and accessed only by the Trio team."
                )
            }
            .font(.footnote)
            .foregroundStyle(Color.secondary)
        }
    }
}
