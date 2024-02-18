import SwiftUI

struct CustomProgressView: View {
    let text: String

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack(alignment: .center) {
            RoundedRectangle(cornerRadius: 15)
                .fill(Color(.systemGray4))
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .shadow(
                    color: colorScheme == .dark ? Color(red: 0.02745098039, green: 0.1098039216, blue: 0.1411764706) :
                        Color.black.opacity(0.33),
                    radius: 3
                )
                .padding(.horizontal, 10)
                .frame(maxHeight: UIScreen.main.bounds.height / 6)

            ProgressView {
                Text(text)
            }
        }
    }
}
