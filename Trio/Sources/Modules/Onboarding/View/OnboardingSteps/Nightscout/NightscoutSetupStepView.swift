import SwiftUI

struct NightscoutSetupStepView: View {
    @Bindable var state: Onboarding.StateModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Nightscout use is entirely optional. You can also setup Nightscout at a later time.")
                .font(.headline)
                .padding(.horizontal)
                .multilineTextAlignment(.leading)

            ForEach([NightscoutSetupOption.setupNightscout, NightscoutSetupOption.skipNightscoutSetup], id: \.self) { option in
                Button(action: {
                    state.nightscoutSetupOption = option
                }) {
                    HStack {
                        Image(systemName: state.nightscoutSetupOption == option ? "largecircle.fill.circle" : "circle")
                            .foregroundColor(state.nightscoutSetupOption == option ? .accentColor : .secondary)
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

            Text(
                "You can use Nightscout to import your existing therapy settings, or if you prefer, you can only connect to Nightscout, and configure therapy settings from scratch."
            )
            .padding(.horizontal)
            .font(.footnote)
            .foregroundStyle(Color.secondary)
            .multilineTextAlignment(.leading)

            Text("Other third-party services, like Apple Health or Tidepool, can be added later through the settings menu.")
                .padding(.horizontal)
                .font(.footnote)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.leading)
        }
    }
}
