import SwiftUI

struct RadioButton: View {
    var isSelected: Bool
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: {
            action()
        }) {
            HStack {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                Text(label) // Add label inside the button to make it tappable
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}
