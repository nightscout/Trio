import SwiftUI

/// Renders the "Glucose Bobble" contact image style: the same ring, trend arrow, and glucose
/// number as the HUD's `CurrentGlucoseView` bobble, reusing its `Triangle` shape so the trend
/// arrow matches exactly. Deliberately does NOT reuse `TrendShape`/`CircleShape` — those bundle a
/// `Color.chart` background fill and a drop shadow meant for the HUD's on-screen context, which
/// showed up as an opaque (near-white) disc behind the ring on the transparent contact photo.
///
/// Sized for `ImageRenderer` at a fixed "native" point size — see
/// `ContactPicture.makeGlucoseBobbleImage` for how it's scaled up to the final pixel resolution.
struct GlucoseBobbleContactView: View {
    let glucoseText: String
    let minutesAgoText: String?
    let deltaText: String?
    let glucoseColor: Color
    let rotationDegrees: Double

    /// `ContactPicture.makeGlucoseBobbleImage` reads `Layout.nativeSize` to size the
    /// `ImageRenderer`'s output, so the rendered canvas exactly matches this view's own layout.
    enum Layout {
        static let nativeSize: CGFloat = 228
        // The ring fills most of the canvas; only the small gap+arrow overhang is reserved as
        // margin, so the bobble sits as close to the contact photo's edge as possible.
        static let ringDiameter: CGFloat = 184
        static let ringLineWidth: CGFloat = 9
        static let triangleSize: CGFloat = 30
        static let triangleGap: CGFloat = 3
        static var triangleOffset: CGFloat { ringDiameter / 2 + triangleGap }
        static let textWidth: CGFloat = ringDiameter * 0.74
    }

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
            Group {
                Circle()
                    .stroke(angularGradient, lineWidth: Layout.ringLineWidth)
                    .frame(width: Layout.ringDiameter, height: Layout.ringDiameter)

                Triangle()
                    .fill(triangleColor)
                    .frame(width: Layout.triangleSize, height: Layout.triangleSize)
                    .rotationEffect(.degrees(90))
                    .offset(x: Layout.triangleOffset)
            }
            .rotationEffect(.degrees(rotationDegrees))

            // Numbers need to read clearly at contact-photo thumbnail size, so — unlike the HUD —
            // they're sized to dominate the ring rather than sit delicately inside it.
            VStack(spacing: 4) {
                Text(glucoseText)
                    .font(.system(size: 66, weight: .bold, design: .rounded))
                    .foregroundStyle(glucoseColor)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)

                if minutesAgoText != nil || deltaText != nil {
                    HStack(spacing: 8) {
                        if let minutesAgoText {
                            Text(minutesAgoText)
                        }
                        if let deltaText {
                            Text(deltaText)
                        }
                    }
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                }
            }
            .frame(width: Layout.textWidth)
        }
        .frame(width: Layout.nativeSize, height: Layout.nativeSize)
    }
}
