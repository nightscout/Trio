import LoopKitUI
import SwiftUI

struct PickerView: View {
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>

    @State var value: Int

    private var currentValue: Binding<Int> {
        Binding(
            get: { value },
            set: { newValue in
                self.value = newValue
            }
        )
    }

    var allowedOptions: [Int]
    var formatter: (Int) -> String
    var didChange: ((Int) -> Void)?

    var title: String
    var description: String?

    var body: some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                titleView
                if description != nil {
                    Text(description!).fixedSize(horizontal: false, vertical: true)
                }

                Divider()
                Spacer()

                ResizeablePicker(
                    selection: currentValue,
                    data: self.allowedOptions,
                    formatter: { formatter($0) }
                )
                .padding(.horizontal)

                Spacer()
            }
            .padding(.horizontal)

            ContinueButton(action: {
                didChange?(value)

                // Go back action
                presentationMode.wrappedValue.dismiss()
            })
        }
        .edgesIgnoringSafeArea(.bottom)
        .navigationBarHidden(false)
    }

    @ViewBuilder private var titleView: some View {
        Text(title)
            .font(.title)
            .bold()
    }
}

#Preview {
    PickerView(
        value: 0,
        allowedOptions: [0, 1, 2, 3],
        formatter: { _ in "" },
        didChange: { _ in },
        title: "Preview Title",
        description: "Preview description"
    )
}
