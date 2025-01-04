import SwiftUI

struct WatchOSButtonStyle: ButtonStyle {
    var backgroundGradient = LinearGradient(colors: [
        Color(red: 0.721, green: 0.341, blue: 1),
        Color(red: 0.486, green: 0.545, blue: 0.953),
        Color(red: 0.262, green: 0.733, blue: 0.914)
    ], startPoint: .topLeading, endPoint: .bottomTrailing)
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
            .background(
                backgroundGradient.opacity(configuration.isPressed ? 0.8 : 1.0)
            )
            .clipShape(Circle())
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
