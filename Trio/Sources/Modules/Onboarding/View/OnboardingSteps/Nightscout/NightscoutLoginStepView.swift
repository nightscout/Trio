import SwiftUI

struct NightscoutLoginStepView: View {
    @Bindable var state: Onboarding.StateModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Please enter your credentials:")
                .font(.headline)
                .padding(.horizontal)

            HStack {
                TextField("URL", text: $state.url)
                    .disableAutocorrection(true)
                    .textContentType(.URL)
                    .autocapitalization(.none)
                    .keyboardType(.URL)
                if state.message.isNotEmpty && !state.isValidURL {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }.padding()
                .background(Color.chart.opacity(0.45))
                .cornerRadius(10)

            HStack {
                SecureField("API secret", text: $state.secret)
                    .disableAutocorrection(true)
                    .autocapitalization(.none)
                    .textContentType(.password)
                    .keyboardType(.asciiCapable)
            }.padding()
                .background(Color.chart.opacity(0.45))
                .cornerRadius(10)

            Spacer(minLength: 10)

            if state.message.isNotEmpty {
                VStack(alignment: .center) {
                    Text(state.message)
                        .font(.subheadline)
                        .foregroundStyle(Color.orange)
                }
            }

            Button(action: {
                let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                impactHeavy.impactOccurred()
                state.connectToNightscout()
            }) {
                HStack {
                    if state.connecting {
                        ProgressView().padding(.trailing, 10)
                    }
                    Text(state.connecting ? "Connecting..." : "Connect to Nightscout")
                        .bold()
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            }
            .disabled(state.url.isEmpty || state.secret.isEmpty)
            .buttonStyle(.borderedProminent)
        }
    }
}
