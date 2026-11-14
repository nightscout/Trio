import SwiftUI

/// The profile a therapy editor edits.
struct TherapyProfileBannerInfo: Equatable {
    let name: String
    let isActive: Bool

    /// Nil for an editor of the live settings while Default is the only profile.
    static func make(manager: TherapyProfileManager, profileName: String?) -> TherapyProfileBannerInfo? {
        let active = manager.activeProfileName
        if let profileName {
            return TherapyProfileBannerInfo(name: profileName, isActive: profileName == active)
        }
        guard manager.profiles().count > 1 else { return nil }
        return TherapyProfileBannerInfo(name: active, isActive: true)
    }
}

struct TherapyProfileBanner: View {
    let info: TherapyProfileBannerInfo

    var body: some View {
        HStack {
            Text("Profile \(info.name)")
                .bold()
            Spacer()
            Text(info.isActive ? String(localized: "Active") : String(localized: "Not active"))
                .foregroundStyle(info.isActive ? Color.green : Color.secondary)
        }
        .padding()
        .background(Color.chart.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.top)
        .accessibilityElement(children: .combine)
    }
}
