import SwiftUI

struct AdjustmentIcon: View {
    let systemName: String
    let tint: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(Circle().fill(tint.opacity(0.18)))
            .accessibilityHidden(true)
    }
}

/// The body is two views on purpose, so a parent stack lays out the icon and the text as its own children.
struct AdjustmentLabel: View {
    let systemName: String
    let tint: Color
    let name: String
    let details: String

    var body: some View {
        AdjustmentIcon(systemName: systemName, tint: tint)
        VStack(alignment: .leading, spacing: 1) {
            Text(name)
                .font(.subheadline).fontWeight(.semibold)
            Text(details)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

extension AdjustmentLabel {
    static func forOverride(name: String, details: String) -> AdjustmentLabel {
        AdjustmentLabel(systemName: "clock.arrow.2.circlepath", tint: Color.purple, name: name, details: details)
    }

    static func forTempTarget(name: String, details: String) -> AdjustmentLabel {
        AdjustmentLabel(systemName: "target", tint: Color.loopGreen, name: name, details: details)
    }
}
