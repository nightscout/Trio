import Combine
import LoopKitUI
import SwiftUI

struct DanaRSv1Password: View {
    @Environment(\.dismissAction) private var dismiss

    @State var password: UInt16?

    let nextAction: (UInt16) -> Void

    var body: some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                title
                TextField(
                    LocalizedString("Fill in password", comment: "password placeholder danars v1"),
                    value: $password,
                    format: .number
                )
                .keyboardType(.numberPad)
                .padding(.horizontal)
                Spacer()
            }
            .padding(.horizontal)

            ContinueButton(action: { nextAction(password ?? 0) })
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
        Text(LocalizedString("Password DanaRS v1", comment: "Title for danars v1 password"))
            .font(.title)
            .bold()
            .padding(.horizontal)
        Divider()
            .padding(.bottom)
    }
}

#Preview {
    DanaRSv1Password(nextAction: { _ in })
}
