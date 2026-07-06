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
            Text(text)
                .font(.callout)
                .fontWeight(.bold)
                .fontDesign(.rounded)
                .foregroundStyle(theme.textColor)
                .lineLimit(1)
        }
        .padding(.bottom, -16)
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
