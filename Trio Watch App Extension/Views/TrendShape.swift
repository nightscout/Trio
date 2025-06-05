import SwiftUI

struct Triangle: Shape {
    /// Flag to be able to adjust size based on Apple Watch size
    let deviceType: WatchSize

    private var triangleTipFactor: CGFloat {
        switch deviceType {
        case .watch40mm,
             .watch41mm,
             .watch42mm:
            return 7.5
        case .unknown,
             .watch44mm,
             .watch45mm:
            return 9
        case .watch49mm:
            return 9
        }
    }

    private var triangleBezierFactor: CGFloat {
        switch deviceType {
        case .watch40mm,
             .watch41mm,
             .watch42mm:
            return 5
        case .unknown,
             .watch44mm,
             .watch45mm:
            return 7
        case .watch49mm:
            return 7
        }
    }

    /// Creates a triangle shape pointing to the right
    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Draw the triangle pointing to the right
        path.move(to: CGPoint(x: rect.maxX - triangleTipFactor, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY),
            control: CGPoint(x: rect.midX - triangleBezierFactor, y: rect.midY)
        )
        path.closeSubpath()

        return path
    }
}

/// A view that displays a circular trend indicator with a directional triangle
struct TrendShape: View {
    let isWatchStateDated: Bool
    /// Rotation angle in degrees for the trend direction
    let rotationDegrees: Double
    /// Flag to be able to adjust size based on Apple Watch size
    let deviceType: WatchSize

    // Angular gradient for the outer circle, transitioning through various blues and purples
    private let angularGradient = AngularGradient(
        colors: [
            Color(red: 0.7215686275, green: 0.3411764706, blue: 1), // #B857FF
            Color(red: 0.6235294118, green: 0.4235294118, blue: 0.9803921569), // #9F6CFA
            Color(red: 0.4862745098, green: 0.5450980392, blue: 0.9529411765), // #7C8BF3
            Color(red: 0.3411764706, green: 0.6666666667, blue: 0.9254901961), // #57AAEC
            Color(red: 0.262745098, green: 0.7333333333, blue: 0.9137254902), // #43BBE9
            Color(red: 0.7215686275, green: 0.3411764706, blue: 1) // #B857FF (repeated for seamless transition)
        ],
        center: .center,
        startAngle: .degrees(270),
        endAngle: .degrees(-90)
    )

    private let staleWatchStateGradient = AngularGradient(
        colors: [
            Color.secondary,
            Color.secondary.opacity(0.8),
            Color.secondary.opacity(0.6),
            Color.secondary.opacity(0.4),
            Color.secondary
        ],
        center: .center
    )

    // Color for the direction indicator triangle
    private let triangleColor = Color(red: 0.262745098, green: 0.7333333333, blue: 0.9137254902) // #43BBE9

    private var strokeWidth: CGFloat {
        switch deviceType {
        case .watch40mm:
            return 3
        case .watch41mm,
             .watch42mm:
            return 4
        case .unknown,
             .watch44mm,
             .watch45mm:
            return 4
        case .watch49mm:
            return 5
        }
    }

    private var circleSize: CGFloat {
        switch deviceType {
        case .watch40mm:
            return 72
        case .watch41mm,
             .watch42mm:
            return 74
        case .watch44mm:
            return 82
        case .unknown,
             .watch45mm:
            return 90
        case .watch49mm:
            return 92
        }
    }

    private var triangleSize: CGFloat {
        switch deviceType {
        case .watch40mm,
             .watch41mm,
             .watch42mm:
            return 16
        case .watch44mm:
            return 18
        case .unknown,
             .watch45mm:
            return 20
        case .watch49mm:
            return 20
        }
    }

    private var triangleOffset: CGFloat {
        switch deviceType {
        case .watch40mm:
            return 46
        case .watch41mm,
             .watch42mm:
            return 47.5
        case .watch44mm:
            return 53.5
        case .unknown,
             .watch45mm:
            return 58
        case .watch49mm:
            return 59
        }
    }

    var body: some View {
        ZStack {
            // Outer circle with gradient
            Circle()
                .stroke(isWatchStateDated ? staleWatchStateGradient : angularGradient, lineWidth: strokeWidth)
                .frame(width: circleSize, height: circleSize)
                .background(Circle().fill(Color.black))

            // Triangle with the color of the last gradient color
            Triangle(deviceType: deviceType)
                .fill(triangleColor)
                .frame(width: triangleSize, height: triangleSize)
                .offset(x: triangleOffset)
                .opacity(isWatchStateDated ? 0 : 1)
        }
        .rotationEffect(.degrees(rotationDegrees))
        .shadow(color: Color.black.opacity(0.33), radius: 3)
    }
}
