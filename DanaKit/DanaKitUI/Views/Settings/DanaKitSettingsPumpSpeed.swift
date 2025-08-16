import LoopKitUI
import SwiftUI

struct DanaKitSettingsPumpSpeed: View {
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>

    let speedsAllowed = BolusSpeed.all()
    @State var value: Int

    private var currentValue: Binding<Int> {
        Binding(
            get: { value },
            set: { newValue in
                self.value = newValue
            }
        )
    }

    var didChange: ((BolusSpeed) -> Void)?

    var body: some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                title
                Text(LocalizedString(
                    "The Dana pumps support different delivery speeds. You can set it up here",
                    comment: "Dana delivery speed body"
                )).fixedSize(horizontal: false, vertical: true)

                Divider()
                Spacer()
                ResizeablePicker(
                    selection: currentValue,
                    data: self.speedsAllowed,
                    formatter: { BolusSpeed.init(rawValue: UInt8($0))!.format() }
                )

                Spacer()
            }
            .padding(.horizontal)

            ContinueButton(action: {
                didChange?(BolusSpeed(rawValue: UInt8(value))!)

                // Go back action
                presentationMode.wrappedValue.dismiss()
            })
        }
        .edgesIgnoringSafeArea(.bottom)
        .navigationBarHidden(false)
    }

    @ViewBuilder private var title: some View {
        Text(LocalizedString("Delivery speed", comment: "Title for delivery speed"))
            .font(.title)
            .bold()
    }
}

#Preview {
    DanaKitSettingsPumpSpeed(value: 0)
}
