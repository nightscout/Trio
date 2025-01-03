import SwiftUI

struct SettingInputHintView<HintView: View>: View {
    @Binding var hintDetent: PresentationDetent
    @Binding var shouldDisplayHint: Bool
    var hintLabel: String
    var hintText: HintView
    var sheetTitle: String

    var body: some View {
        NavigationStack {
            List {
                DefinitionRow(
                    term: hintLabel,
                    definition: hintText,
                    fontSize: .body
                )
                .listRowBackground(Color.gray.opacity(0.1))
            }
            .scrollContentBackground(.hidden)
            .navigationBarTitle(sheetTitle, displayMode: .inline)

            Spacer()

            Button {
                shouldDisplayHint.toggle()
            } label: {
                Text("Got it!").bold().frame(maxWidth: .infinity, minHeight: 30, alignment: .center)
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
