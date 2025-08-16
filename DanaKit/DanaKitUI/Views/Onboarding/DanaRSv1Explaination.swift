import LoopKitUI
import SwiftUI

struct DanaRSv1Explaination: View {
    @Environment(\.dismissAction) private var dismiss
    @Environment(\.appName) private var appName

    let nextAction: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            title

            ScrollView {
                VStack(alignment: .leading) {
                    Text(LocalizedString(
                        "NOTE: The DanaRS v1 is not supported (yet). If you have a DanaRS v1 pump available for testing, please contact Bastiaan Verhaar!",
                        comment: "advertise contact DanaRS v1"
                    ))
                        .fontWeight(.bold)
                    Text(LocalizedString(
                        "Before starting with the pairing process, it is recommended to check, and if needed update, the pump password. You can do this by going to the pump settings -> user settings -> password. The default password is 1234, if this is your password, please consider changing it",
                        comment: "check password text for danars v1"
                    ))
                        .padding(.bottom)

                    Text(String(
                        format: LocalizedString(
                            "After setting up the insulin type and bolus speed, you will see all the found Dana pumps. Select the pump you want to link with %1$@.",
                            comment: "General subtext for dana (1: appName)"
                        ),
                        appName
                    ))

                    HStack {
                        Spacer()
                        Image(danaImage: "pairing_request")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 150)
                        Spacer()
                    }
                    .padding(.vertical, 10)

                    Text(String(
                        format: LocalizedString(
                            "During the pairing process, your DanaRS v1 will show a pairing prompt while you iPhone will show a prompt for a pairing code. On your pump, select OK and type the code on your iPhone. After that, %1$@ is ready to communicate with your DanaRS v1",
                            comment: "Subtext for danars v1 (1: appName)"
                        ),
                        appName
                    ))

                    Spacer()
                }
                .padding(.horizontal)
            }

            ContinueButton(disabled: .constant(true), action: nextAction)
        }
        .edgesIgnoringSafeArea(.bottom)
        .navigationBarHidden(false)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(LocalizedString("Cancel", comment: "Cancel button title"), action: {
                    self.dismiss()
                })
            }
        }
    }

    @ViewBuilder private var title: some View {
        Text(LocalizedString("Setting up DanaRS v1", comment: "Title for danars v1 explaination"))
            .font(.title)
            .bold()
            .padding(.horizontal)
        Divider()
            .padding(.bottom)
    }
}

#Preview {
    DanaRSv1Explaination(nextAction: {})
}
