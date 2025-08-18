import LoopKit
import LoopKitUI
import SwiftUI

struct InsulinTypeConfirmation: View {
    @Environment(\.dismissAction) private var dismiss

    @State private var insulinType: InsulinType?
    private var supportedInsulinTypes: [InsulinType]
    private var didConfirm: (InsulinType) -> Void

    init(initialValue: InsulinType, supportedInsulinTypes: [InsulinType], didConfirm: @escaping (InsulinType) -> Void) {
        _insulinType = State(initialValue: initialValue)
        self.supportedInsulinTypes = supportedInsulinTypes
        self.didConfirm = didConfirm
    }

    var body: some View {
        VStack(alignment: .leading) {
            title

            ScrollView {
                InsulinTypeChooser(insulinType: $insulinType, supportedInsulinTypes: supportedInsulinTypes)
                    .padding(.horizontal)
            }

            Spacer()

            ContinueButton(action: {
                guard let insulinType = insulinType else {
                    return
                }
                didConfirm(insulinType)
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
        Text(LocalizedString("Select insulin type", comment: "Title for insulin type"))
            .font(.title)
            .bold()
            .padding([.bottom, .horizontal])

        Text(LocalizedString(
            "Select the type of insulin that you will be using in this pump.",
            comment: "Title text for insulin type confirmation page"
        ))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal)

        Divider()
            .padding(.vertical)
    }
}

struct InsulinTypeConfirmation_Previews: PreviewProvider {
    static var previews: some View {
        InsulinTypeConfirmation(initialValue: .novolog, supportedInsulinTypes: InsulinType.allCases, didConfirm: { _ in })
    }
}
