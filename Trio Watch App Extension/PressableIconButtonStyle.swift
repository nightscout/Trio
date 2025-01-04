import SwiftUI

struct PressableIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.clear)
            .opacity(configuration.isPressed ? 0.3 : 1.0) // Change opacity when pressed
            .animation(.easeInOut(duration: 0.25), value: configuration.isPressed) // Smooth transition
    }
}
