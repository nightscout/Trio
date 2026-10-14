import SwiftUI

struct StatSelectionPopover<Content: View>: View {
    let title: String
    let tint: Color
    @ViewBuilder let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: title)
                .font(.subheadline).bold().foregroundStyle(Color.secondary)
            Divider()
            content()
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.bgDarkBlue.opacity(0.9) : Color.white.opacity(0.95))
                .shadow(color: Color.secondary, radius: 2)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(tint, lineWidth: 2))
        }
    }
}
