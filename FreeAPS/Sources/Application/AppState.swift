import Foundation
import Observation
import SwiftUICore
import UIKit

@Observable class AppState {
    func trioBackgroundColor(for colorScheme: ColorScheme) -> LinearGradient {
        colorScheme == .dark
            ? LinearGradient(
                gradient: Gradient(colors: [Color.bgDarkBlue, Color.bgDarkerDarkBlue]),
                startPoint: .top,
                endPoint: .bottom
            )
            : LinearGradient(
                gradient: Gradient(colors: [Color.gray.opacity(0.1)]),
                startPoint: .top,
                endPoint: .bottom
            )
    }

    func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        appearance.backgroundColor = UIColor.clear

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}
