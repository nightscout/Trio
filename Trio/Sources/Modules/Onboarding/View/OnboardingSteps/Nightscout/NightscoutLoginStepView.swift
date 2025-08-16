import SwiftUI

struct NightscoutLoginStepView: View {
    @Bindable var state: Onboarding.StateModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Please enter your credentials:")
                .font(.headline)
                .padding(.horizontal)

            HStack {
                TextField("URL", text: $state.nightscoutUrl)
                    .disableAutocorrection(true)
                    .textContentType(.URL)
                    .autocapitalization(.none)
                    .keyboardType(.URL)
                if state.nightscoutResponseMessage.isNotEmpty && !state.isValidNightscoutURL {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }.padding()
                .background(Color.chart.opacity(0.65))
                .cornerRadius(10)

            HStack {
                SecureField("API secret", text: $state.nightscoutSecret)
                    .disableAutocorrection(true)
                    .autocapitalization(.none)
                    .textContentType(.password)
                    .keyboardType(.asciiCapable)
            }.padding()
                .background(Color.chart.opacity(0.65))
                .cornerRadius(10)

            Spacer(minLength: 10)

            Button(action: {
                let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                impactHeavy.impactOccurred()
                state.connectToNightscout()
            }) {
                HStack {
                    if state.isConnectingToNS {
                        ProgressView().padding(.trailing, 10)
                    }
                    Text(state.isConnectingToNS ? "Connecting..." : "Connect to Nightscout")
                        .bold()
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            }
            .disabled(state.isConnectedToNS || state.nightscoutUrl.isEmpty || state.nightscoutSecret.isEmpty)
            .buttonStyle(.borderedProminent)

            if state.nightscoutResponseMessage.isNotEmpty {
                VStack(alignment: .center) {
                    Text(state.nightscoutResponseMessage)
                        .font(.subheadline)
                        .foregroundStyle(Color.orange)
                }
            } else if state.isConnectedToNS {
                HStack {
                    Spacer()
                    Text("Connected")
                        .font(.subheadline)
                        .foregroundColor(.green)
                    ZStack {
                        Image(systemName: "network")
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.caption2)
                            .offset(x: 9, y: 6)
                    }
                    Spacer()
                }
            }
        }
    }
}
