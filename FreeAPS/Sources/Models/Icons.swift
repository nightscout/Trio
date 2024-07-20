
import Foundation
import UIKit

enum Icon_: String, CaseIterable, Identifiable {
<<<<<<< HEAD
    case primary = "oiapsBlack"
    case oiAPSWhiteShadow
    case oiapsColorBG
    case oiapsWhite
    case oiaps3D
    case wilford = "diabeetus"
    case catWithPod
    case catWithPodWhite = "catWithPodWhiteBG"
    case loop = "OiAPS_Loop"
=======
    case primary = "trioBlack"
    case trioWhiteShadow
    case trioColorBG
    case trioWhite
    case trio3D
    case wilford = "diabeetus"
    case catWithPod
    case catWithPodWhite = "catWithPodWhiteBG"
    case loop = "trioLoop"
>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133
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
