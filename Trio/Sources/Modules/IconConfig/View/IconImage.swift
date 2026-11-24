import SwiftUI

struct IconImage: View {
    var icon: Icon_

    var body: some View {
        Image(icon.rawValue)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(minHeight: 57, maxHeight: 1024)
            .clipShape(.rect(cornerRadius: 10))
            .shadow(radius: 10)
            .padding()
            .accessibilityHidden(true)
    }
}

#Preview {
    IconImage(icon: .primary)
}
