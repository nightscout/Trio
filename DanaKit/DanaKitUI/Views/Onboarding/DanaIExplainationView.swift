import LoopKitUI
import SwiftUI

struct DanaIExplainationView: View {
    @Environment(\.dismissAction) private var dismiss
    @Environment(\.appName) var appName

    let nextAction: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            title

            ScrollView {
                VStack(alignment: .leading) {
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
                            "During the pairing process, your Dana-i will show a pairing prompt while your iPhone will show a prompt for a pairing code. On you pump, select OK and type the 6-digit code in screen on your iPhone. After that, %1$@ is ready to communicate with your Dana-i",
                            comment: "Subtext for dana-i (1: appName)"
                        ),
                        appName
                    ))

                    Spacer()
                }
                .padding(.horizontal)
            }

            ContinueButton(action: nextAction)
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
        Text(LocalizedString("Setting up Dana-i", comment: "Title for dana-i explaination"))
            .font(.title)
            .bold()
            .padding(.horizontal)
        Divider()
            .padding(.bottom)
    }
}

#Preview {
    DanaIExplainationView(nextAction: {})
}
