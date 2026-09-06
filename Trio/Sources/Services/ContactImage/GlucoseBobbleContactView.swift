import SwiftUI

/// The "Glucose Bobble" contact image style: same ring, trend arrow and glucose number as the
/// HUD's `CurrentGlucoseView` bobble, reusing its `Triangle` shape. Rendered by `ContactPicture`
/// via `ImageRenderer` at `Layout.nativeSize` and scaled up from there.
struct GlucoseBobbleContactView: View {
    let glucoseText: String
    let minutesAgoText: String?
    let deltaText: String?
    let glucoseColor: Color
    let rotationDegrees: Double

    enum Layout {
        static let nativeSize: CGFloat = 256
        static let ringDiameter: CGFloat = 184
        static let ringLineWidth: CGFloat = 9
        static let triangleSize: CGFloat = 26

        // Circle().stroke centers the stroke on the path, so the ring's outer edge sits
        // ringLineWidth / 2 past ringDiameter / 2. Offset the triangle from there, not the bare
        // radius, or it overlaps the ring.
        static var ringOuterRadius: CGFloat { ringDiameter / 2 + ringLineWidth / 2 }
        static var triangleOffset: CGFloat { ringOuterRadius + triangleSize / 2 }
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
            // Must be a ZStack, not a Group: a modifier on a Group applies to each child
            // separately, so rotationEffect would spin the triangle around its own offset
            // instead of orbiting it around the ring.
            ZStack {
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
