
import Foundation
import UIKit

enum Icon_: String, CaseIterable, Identifiable {
    case primary = "OiAPS_Icon"
    case text = "iAPS"
    case podBlack = "podTemplateBlack"
    case popWhite = "podTemplateWhite"
    case cyan = "iAPS_Loop_Cyan_Text"
    case podPurple
    case podcolorful = "pod_colorful"
    case catWithPod
    case catWithPodWhite = "catWithPodWhiteBG"
    case loopWhiteText = "iAPS_Loop_White_Text"
    case loopText = "iAPS_Loop_Text"
    case black = "iAPS_Black_Black"
    case clean = "iAPS_Clean"
    case purple = "iAPS_Purple"
    case glow = "iAPS_Glow_BG"
    case gray = "iAPS_Gray"
    case whiteAndGray = "iAPS_WhiteAndGray"
    case grayAndLoopNoButtons = "iAPS_NoButtons_Gray_White_BG"
    case purpleBG = "iAPS_Purple_BG"
    case whiteBG = "iAPS_White_BG"
    case loop = "iAPS_Loop"
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
