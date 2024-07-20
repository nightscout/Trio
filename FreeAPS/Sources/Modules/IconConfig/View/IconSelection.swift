
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
                    }
                }
            }
        }
    }
}

struct IconSelectionRootView_Previews: PreviewProvider {
    static var previews: some View {
        IconSelection()
            .environmentObject(Icons())
    }
}
