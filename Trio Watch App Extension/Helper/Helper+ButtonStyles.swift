import SwiftUI

struct WatchOSButtonStyle: ButtonStyle {
    var foregroundColor: Color = .white
    var fontSize: Font = .title2

    private var is40mm: Bool {
        let size = WKInterfaceDevice.current().screenBounds.size
        return size.height < 225 && size.width < 185
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(fontSize)
            .fontWeight(is40mm ? .medium : .semibold)
            .padding(is40mm ? 6 : 8)
            .background(Color.tabBar.opacity(configuration.isPressed ? 0.8 : 1.0))
            .clipShape(Circle())
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct PressableIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.clear)
            .opacity(configuration.isPressed ? 0.3 : 1.0) // Change opacity when pressed
            .animation(.easeInOut(duration: 0.25), value: configuration.isPressed) // Smooth transition
    }
}
