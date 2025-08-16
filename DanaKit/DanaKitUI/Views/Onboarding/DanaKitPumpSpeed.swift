import LoopKitUI
import SwiftUI

struct DanaKitPumpSpeed: View {
    @Environment(\.dismissAction) private var dismiss

    let speedsAllowed = BolusSpeed.all()
    @State var speedDefault = Int(BolusSpeed.speed12.rawValue)

    var next: ((BolusSpeed) -> Void)?

    var body: some View {
        VStack(alignment: .leading) {
            title

            VStack(alignment: .leading) {
                Spacer()
                ResizeablePicker(
                    selection: $speedDefault,
                    data: self.speedsAllowed,
                    formatter: { BolusSpeed.init(rawValue: UInt8($0))!.format() }
                )
                Spacer()
            }
            .padding(.horizontal)

            ContinueButton(action: {
                guard let speed = BolusSpeed(rawValue: UInt8($speedDefault.wrappedValue)) else {
                    return
                }

                next?(speed)
            })
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
        Text(LocalizedString("Delivery speed", comment: "Title for delivery speed"))
            .font(.title)
            .bold()
            .padding(.horizontal)
        Text(LocalizedString(
            "The Dana pumps support different delivery speeds. You can set it up here, but also in the settings menu",
            comment: "Dana delivery speed body"
        ))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal)

        Divider()
    }
}

#Preview {
    DanaKitPumpSpeed()
}
