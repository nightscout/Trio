
import SwiftUI

struct IconImage: View {
    var icon: Icon_

    var body: some View {
        Label {
            Text(icon.rawValue)
        } icon: {
            Image(icon.rawValue)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(minHeight: 57, maxHeight: 1024)
                .cornerRadius(10)
                .shadow(radius: 10)
                .padding()
        }
        .labelStyle(.iconOnly)
    }
}

struct IconImage_Previews: PreviewProvider {
    static var previews: some View {
        IconImage(icon: Icon_.primary)
            .previewInterfaceOrientation(.portrait)
    }
}
