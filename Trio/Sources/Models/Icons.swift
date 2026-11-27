import SwiftUI
import UIKit

enum Icon_: String, CaseIterable, Identifiable {
    case primary = "liqglass"
    case trioWhiteShadow
    case trioColorBG
    case trioWhite
    case trioBlack
    case trioCircledNoBackground
    case trio3D
    case wilford = "diabeetus"
    case catWithPod
    case catWithPodWhite = "catWithPodWhiteBG"
    var id: String { rawValue }
}

@MainActor final class Icons: ObservableObject {
    @Published private(set) var appIcon: Icon_

    init() {
        // An icon removed or renamed in a later build falls back to the primary one.
        appIcon = UIApplication.shared.alternateIconName.flatMap(Icon_.init(rawValue:)) ?? .primary
    }

    func setAlternateAppIcon(icon: Icon_) {
        guard icon != appIcon else { return }
        Task {
            do {
                try await UIApplication.shared.setAlternateIconName(icon == .primary ? nil : icon.rawValue)
                appIcon = icon
            } catch {
                warning(.ui, "Changing the app icon failed", error: error)
            }
        }
    }
}
