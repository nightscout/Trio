import LoopKit
import LoopKitUI
import SwiftUI

struct InsulinTypeView: View {
    @Environment(\.dismissAction) private var dismiss

    @State private var insulinType: InsulinType?
    private var supportedInsulinTypes: [InsulinType]
    private var didConfirm: (InsulinType) -> Void

    init(initialValue: InsulinType, supportedInsulinTypes: [InsulinType], didConfirm: @escaping (InsulinType) -> Void) {
        _insulinType = State(initialValue: initialValue)
        self.supportedInsulinTypes = supportedInsulinTypes
        self.didConfirm = didConfirm
    }

    func continueWithType(_ insulinType: InsulinType?) {
        if let insulinType = insulinType {
            didConfirm(insulinType)
        } else {
            assertionFailure()
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            title

            ScrollView {
                InsulinTypeChooser(insulinType: $insulinType, supportedInsulinTypes: supportedInsulinTypes)
                    .padding(.horizontal)
            }

            Spacer()

            ContinueButton(action: { self.continueWithType(insulinType) })
        }
        .edgesIgnoringSafeArea(.bottom)
        .navigationBarHidden(false)
    }

    @ViewBuilder private var title: some View {
        Text(LocalizedString("Select insulin type", comment: "Title for insulin type"))
            .font(.title)
            .bold()
            .padding(.horizontal)

        Text(LocalizedString(
            "Select the type of insulin that you will be using in this pump",
            comment: "Title text for insulin type confirmation page"
        ))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal)

        Divider()
            .padding(.vertical)
    }
}

struct InsulinTypeView_Previews: PreviewProvider {
    static var previews: some View {
        InsulinTypeView(initialValue: .novolog, supportedInsulinTypes: InsulinType.allCases, didConfirm: { _ in })
    }
}
