
import SwiftUI

struct IconSelection: View {
    @EnvironmentObject var model: Icons

    var body: some View {
        let columns = Array(repeating: GridItem(.adaptive(minimum: 114, maximum: 1024), spacing: 0), count: 3)

        VStack {
            HStack {
                Text("Trio Icon")
                    .font(.title)
                IconImage(icon: model.appIcon)
                    .frame(maxHeight: 114)
            }

            Divider()

            ScrollView {
                LazyVGrid(columns: columns) {
                    ForEach(Icon_.allCases) { icon in
                        Button {
                            model.setAlternateAppIcon(icon: icon)
                        } label: {
                            IconImage(icon: icon)
                        }
                        .accessibilityLabel(Text(iconDisplayName(icon)))
                        .accessibilityAddTraits(model.appIcon == icon ? [.isButton, .isSelected] : .isButton)
                    }
                }
            }
        }
    }

    /// Splits the internal asset id (e.g. "trioColorBG") into spoken words so VoiceOver
    /// announces a readable icon name instead of a run-together identifier.
    private func iconDisplayName(_ icon: Icon_) -> String {
        var result = ""
        for character in icon.rawValue {
            if character.isUppercase, !result.isEmpty { result.append(" ") }
            result.append(character)
        }
        return result.prefix(1).capitalized + result.dropFirst()
    }
}

struct IconSelectionRootView_Previews: PreviewProvider {
    static var previews: some View {
        IconSelection()
            .environmentObject(Icons())
    }
}
