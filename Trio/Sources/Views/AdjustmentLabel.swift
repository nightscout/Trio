import SwiftUI

struct AdjustmentIcon: View {
    let systemName: String
    let tint: Color
    var diameter: CGFloat = 30

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: diameter / 2, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(tint.opacity(0.18)))
            .accessibilityHidden(true)
    }
}

/// The regular body is two views on purpose, so a parent stack lays out the icon and the text as its own children.
struct AdjustmentLabel: View {
    enum Style {
        case regular
        /// For small surfaces where the adjustment must not outweigh the glucose value.
        case compact
    }

    let systemName: String
    let tint: Color
    let name: String
    let details: String
    var style: Style = .regular

    var body: some View {
        switch style {
        case .regular:
            AdjustmentIcon(systemName: systemName, tint: tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.subheadline).fontWeight(.semibold)
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .compact:
            HStack(spacing: 6) {
                AdjustmentIcon(systemName: systemName, tint: tint, diameter: 20)
                // One text so the details wrap instead of being cut, because they can say that SMBs are off.
                let nameText = Text(name).font(.footnote).fontWeight(.semibold)
                let detailsText = Text(details).font(.caption).foregroundStyle(.secondary)
                Text("\(nameText) \(detailsText)")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension AdjustmentLabel {
    static func forOverride(name: String, details: String, style: Style = .regular) -> AdjustmentLabel {
        AdjustmentLabel(systemName: "clock.arrow.2.circlepath", tint: Color.purple, name: name, details: details, style: style)
    }

    static func forTempTarget(name: String, details: String, style: Style = .regular) -> AdjustmentLabel {
        AdjustmentLabel(systemName: "target", tint: Color.loopGreen, name: name, details: details, style: style)
    }
}
