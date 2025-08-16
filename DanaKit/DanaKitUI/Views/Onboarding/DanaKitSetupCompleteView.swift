import LoopKitUI
import SwiftUI

struct DanaKitSetupCompleteView: View {
    var finish: (() -> Void)?
    var friendlyPumpModelName: String
    var imageName: String

    var body: some View {
        VStack(alignment: .leading) {
            title
            VStack(alignment: .leading) {
                Text(
                    LocalizedString("Your ", comment: "Dana setup complete p1") + friendlyPumpModelName +
                        LocalizedString(" is ready to be used!", comment: "Dana setup complete p2")
                )

                HStack {
                    Spacer()
                    Image(danaImage: imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 200)
                    Spacer()
                }
                .padding(.vertical)

                Text(LocalizedString(
                    "Note: You Dana pump has a special setting which allows you to silence your Dana pump beeps. To enable this, please contact your Dana distributor",
                    comment: "Dana setup SMB setting"
                ))
            }
            .padding(.horizontal)
            Spacer()

            ContinueButton(text: LocalizedString("Finish", comment: "Text for finish button"), action: { finish?() })
        }
        .edgesIgnoringSafeArea(.bottom)
        .navigationBarHidden(false)
    }

    @ViewBuilder private var title: some View {
        Text(LocalizedString("Setup Complete", comment: "Title for setup complete"))
            .font(.title)
            .bold()
            .padding(.horizontal)

        Divider()
            .padding(.bottom)
    }
}

#Preview {
    DanaKitSetupCompleteView(finish: {}, friendlyPumpModelName: "Dana-i", imageName: "danai")
}
