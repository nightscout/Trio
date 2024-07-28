import SwiftUI

struct SettingInputHintView: View {
    @Binding var hintDetent: PresentationDetent
    @Binding var shouldDisplayHint: Bool
    var hintLabel: String
    var hintText: String
    var sheetTitle: String
    var body: some View {
        NavigationStack {
            List {
                DefinitionRow(
                    term: hintLabel,
                    definition: hintText,
                    fontSize: .body
                )
            }
            .navigationBarTitle(sheetTitle, displayMode: .inline)

            Spacer()

            Button {
                shouldDisplayHint.toggle()
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
