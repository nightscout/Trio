
import Foundation
import UIKit

enum Icon_: String, CaseIterable, Identifiable {
    case primary = "oiapsBlack"
    case text = "Open-iAPS"
    case catWithPod
    case catWithPodWhite = "catWithPodWhiteBG"
    case loop = "OiAPS_Loop"
    case diabeetus
    case oiapsWhite
    case oiapsWhiteShadow
    case oiapsColorBG
    var id: String { rawValue }
}

class Icons: ObservableObject, Equatable {
    @Published var appIcon: Icon_ = .primary

    static func == (lhs: Icons, rhs: Icons) -> Bool {
        lhs.appIcon == rhs.appIcon
    }

    func setAlternateAppIcon(icon: Icon_) {
        let iconName: String? = (icon != .primary) ? icon.rawValue : nil

        guard UIApplication.shared.alternateIconName != iconName else { return }

        UIApplication.shared.setAlternateIconName(iconName) { error in
            if let error = error {
                print("Failed request to update the app’s icon: \(error)")
            }
        }

        appIcon = icon
    }

    init() {
        let iconName = UIApplication.shared.alternateIconName

        if iconName == nil {
            appIcon = .primary
        } else {
            appIcon = Icon_(rawValue: iconName!)!
        }
    }
}
