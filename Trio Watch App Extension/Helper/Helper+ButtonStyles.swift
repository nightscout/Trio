import SwiftUI

struct WatchOSButtonStyle: ButtonStyle {
    let deviceType: WatchSize
    var foregroundColor: Color = .white
    var fontSize: Font = .title2

    @Environment(\.isEnabled) private var isEnabled: Bool

    private var fontWeight: Font.Weight {
        switch deviceType {
        case .watch40mm:
            return .medium
        case .watch41mm:
            return .medium
        case .watch42mm:
            return .medium
        case .watch44mm:
            return .semibold
        case .watch45mm:
            return .semibold
        case .watch49mm:
            return .bold
        case .unknown:
            return .semibold
        }
    }

    private var buttonPadding: CGFloat {
        switch deviceType {
        case .watch40mm:
            return 6
        case .watch41mm:
            return 6
        case .watch42mm:
            return 6
        case .watch44mm:
            return 8
        case .watch45mm:
            return 8
        case .watch49mm:
            return 8
        case .unknown:
            return 8
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        var buttonBackground: Color {
            if isEnabled {
                return Color.tabBar.opacity(configuration.isPressed ? 0.8 : 1.0)
            } else {
                return Color.tabBar.opacity(0.4)
            }
        }

        configuration.label
            .font(fontSize)
            .fontWeight(fontWeight)
            .padding(buttonPadding)
            .background(buttonBackground)
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
