import SwiftUI

/// Renders the "Glucose Bobble" contact image style: the same ring, trend arrow, and glucose
/// number as the HUD's `CurrentGlucoseView` bobble, reusing its shapes (`TrendShape`, `CircleShape`,
/// `TriangleShape`) so the contact photo matches the main screen 1:1.
///
/// Sized for `ImageRenderer` at a fixed "native" point size — see
/// `ContactPicture.makeGlucoseBobbleImage` for how it's scaled up to the final pixel resolution.
struct GlucoseBobbleContactView: View {
    let glucoseText: String
    let deltaText: String?
    let glucoseColor: Color
    let rotationDegrees: Double

    private var triangleColor: Color {
        Color(red: 0.262745098, green: 0.7333333333, blue: 0.9137254902)
    }

    private var angularGradient: AngularGradient {
        AngularGradient(colors: [
            Color(red: 0.7215686275, green: 0.3411764706, blue: 1),
            Color(red: 0.6235294118, green: 0.4235294118, blue: 0.9803921569),
            Color(red: 0.4862745098, green: 0.5450980392, blue: 0.9529411765),
            Color(red: 0.3411764706, green: 0.6666666667, blue: 0.9254901961),
            Color(red: 0.262745098, green: 0.7333333333, blue: 0.9137254902),
            Color(red: 0.7215686275, green: 0.3411764706, blue: 1)
        ], center: .center, startAngle: .degrees(270), endAngle: .degrees(-90))
    }

    var body: some View {
        ZStack {
            TrendShape(gradient: angularGradient, color: triangleColor, showArrow: true)
                .rotationEffect(.degrees(rotationDegrees))

            // Numbers need to read clearly at contact-photo thumbnail size, so — unlike the HUD —
            // they're sized to dominate the ring rather than sit delicately inside it.
            VStack(spacing: 6) {
                Text(glucoseText)
                    .font(.system(size: 58, weight: .bold, design: .rounded))
                    .foregroundStyle(glucoseColor)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)

                if let deltaText, !deltaText.isEmpty {
                    Text(deltaText)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
            }
            .frame(width: 118)
        }
        // Wide enough to contain the ring plus the trend triangle's offset (and its drop shadow)
        // at any rotation. Keep in sync with `ContactPicture.makeGlucoseBobbleImage`'s nativeSize.
        .frame(width: 230, height: 230)
    }
}
