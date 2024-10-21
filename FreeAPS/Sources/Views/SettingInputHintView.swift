import SwiftUI

struct SettingInputHintView<HintView: View>: View {
    @Binding var hintDetent: PresentationDetent
    @Binding var shouldDisplayHint: Bool
    var hintLabel: String
    var hintText: HintView
    var sheetTitle: String

    @Environment(\.colorScheme) private var colorScheme
    private var color: LinearGradient {
        colorScheme == .dark ? LinearGradient(
            gradient: Gradient(colors: [
                Color.bgDarkBlue,
                Color.bgDarkerDarkBlue
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
            :
            LinearGradient(
                gradient: Gradient(colors: [Color.gray.opacity(0.1)]),
                startPoint: .top,
                endPoint: .bottom
            )
    }

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
