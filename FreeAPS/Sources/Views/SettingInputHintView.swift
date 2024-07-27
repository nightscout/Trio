import SwiftUI

struct SettingInputHintView: View {
    @Binding var hintDetent: PresentationDetent
    @Binding var showHint: Bool
    var hintLabel: String
    var hintText: String
    var sheetTitle: String

    var body: some View {
        NavigationStack {
            List {
                DefinitionRow(
                    term: hintLabel,
                    definition: hintText
                )
            }
            .padding(.trailing, 10)
            .navigationBarTitle(sheetTitle, displayMode: .inline)

            Spacer()

            Button {
                showHint.toggle()
            } label: {
                Text("Got it!")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.bordered)
            .padding(.top)
        }
        .padding()
        .presentationDetents(
            [.fraction(0.9), .large],
            selection: $hintDetent
        )
    }
}
