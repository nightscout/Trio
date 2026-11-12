import SwiftUI

/// Status badge below the glucose bobble — text-only, no fill or border.
struct SensorStatusTagView: View {
    let text: String
    let theme: SensorStatusTagTheme
    var iconSystemName: String?

    var body: some View {
        HStack(spacing: 4) {
            if let iconSystemName {
                Image(systemName: iconSystemName)
                    .font(.callout)
                    .fontWeight(.bold)
                    .foregroundStyle(theme.textColor)
            }
            // A tag with a line break ("Sensor issue:" / "not reliable") is laid out by its first line, exactly
            // where a one-line tag sits; the second hangs below it, a little closer than a full line, so it
            // keeps clear of the carbs under it.
            styled(Text(firstLine))
                .lineLimit(1)
                .overlay(alignment: .top) {
                    if let secondLine {
                        styled(Text(secondLine))
                            .lineLimit(1)
                            .fixedSize()
                            .alignmentGuide(.top) { d in d[.top] - d.height + Self.lineTightening }
                    }
                }
        }
        .padding(.bottom, -16)
    }

    /// How much closer than a full line the second line sits.
    private static let lineTightening: CGFloat = 5

    private var firstLine: String {
        String(text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
    }

    private var secondLine: String? {
        let parts = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        return parts.count > 1 ? String(parts[1]) : nil
    }

    private func styled(_ text: Text) -> some View {
        text
            .font(.callout)
            .fontWeight(.bold)
            .fontDesign(.rounded)
            .foregroundStyle(theme.textColor)
            .multilineTextAlignment(.center)
    }
}

enum SensorStatusTagTheme {
    case green
    case orange
    case red
    case secondary

    var textColor: Color {
        switch self {
        case .green: return Color.loopGreen
        case .orange: return Color.orange
        case .red: return Color.loopRed
        case .secondary: return Color.secondary
        }
    }
}

#Preview("Tag — all themes") {
    VStack(spacing: 12) {
        SensorStatusTagView(text: "5d 14h", theme: .green)
        SensorStatusTagView(text: "22h left", theme: .orange)
        SensorStatusTagView(text: "warming up", theme: .secondary)
        SensorStatusTagView(text: "calibrate", theme: .secondary)
        SensorStatusTagView(text: "sensor expired", theme: .red)
        SensorStatusTagView(text: "sensor error", theme: .red)
    }
    .padding(40)
    .background(Color.black)
    .preferredColorScheme(.dark)
}
