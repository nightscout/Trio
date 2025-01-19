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

    // Color for the direction indicator triangle
    private let triangleColor = Color(red: 0.262745098, green: 0.7333333333, blue: 0.9137254902) // #43BBE9

    private var strokeWidth: CGFloat {
        switch deviceType {
        case .watch40mm,
             .watch41mm,
             .watch42mm:
            return 4

        case .unknown,
             .watch44mm,
             .watch45mm:
            return 5
        case .watch49mm:
            return 5
        }
    }

    private var circleSize: CGFloat {
        switch deviceType {
        case .watch40mm,
             .watch41mm,
             .watch42mm:
            return 74
        case .unknown,
             .watch44mm,
             .watch45mm:
            return 92
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
        case .unknown,
             .watch44mm,
             .watch45mm:
            return 20
        case .watch49mm:
            return 20
        }
    }

    private var triangleOffset: CGFloat {
        switch deviceType {
        case .watch40mm,
             .watch41mm,
             .watch42mm:
            return 47.5
        case .unknown,
             .watch44mm,
             .watch45mm:
            return 59
        case .watch49mm:
            return 59
        }
    }

    var body: some View {
        ZStack {
            // Outer circle with gradient
            Circle()
                .stroke(angularGradient, lineWidth: strokeWidth)
                .frame(width: circleSize, height: circleSize)
                .background(Circle().fill(Color.black))

            // Triangle with the color of the last gradient color
            Triangle(deviceType: deviceType)
                .fill(triangleColor)
                .frame(width: triangleSize, height: triangleSize)
                .offset(x: triangleOffset)
        }
        .rotationEffect(.degrees(rotationDegrees))
        .shadow(color: Color.black.opacity(0.33), radius: 3)
    }
}

// MARK: - TREND SHAPE PREVIEWS
struct TrendShape_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            TrendShape(rotationDegrees: 0,  deviceType: .watch40mm)
                .previewDisplayName("TrendShape • 40mm")

            TrendShape(rotationDegrees: 0,  deviceType: .watch41mm)
                .previewDisplayName("TrendShape • 41mm")

            TrendShape(rotationDegrees: 0,  deviceType: .watch42mm)
                .previewDisplayName("TrendShape • 42mm")

            TrendShape(rotationDegrees: 0,  deviceType: .watch44mm)
                .previewDisplayName("TrendShape • 44mm")

            TrendShape(rotationDegrees: 0,  deviceType: .watch45mm)
                .previewDisplayName("TrendShape • 45mm")

            TrendShape(rotationDegrees: 0,  deviceType: .watch49mm)
                .previewDisplayName("TrendShape • 49mm")
        }
        .padding()
        // Optional: to let each preview "shrink to fit" rather than fill the entire simulator screen:
        // .previewLayout(.sizeThatFits)
    }
}

// MARK: - TRIANGLE PREVIEWS
struct Triangle_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            Triangle(deviceType: .watch40mm)
                .fill(Color.blue)
                .frame(width: 50, height: 50)
                .previewDisplayName("Triangle • 40mm")

            Triangle(deviceType: .watch41mm)
                .fill(Color.green)
                .frame(width: 50, height: 50)
                .previewDisplayName("Triangle • 41mm")

            Triangle(deviceType: .watch42mm)
                .fill(Color.purple)
                .frame(width: 50, height: 50)
                .previewDisplayName("Triangle • 42mm")

            Triangle(deviceType: .watch44mm)
                .fill(Color.red)
                .frame(width: 50, height: 50)
                .previewDisplayName("Triangle • 44mm")

            Triangle(deviceType: .watch45mm)
                .fill(Color.orange)
                .frame(width: 50, height: 50)
                .previewDisplayName("Triangle • 45mm")

            Triangle(deviceType: .watch49mm)
                .fill(Color.pink)
                .frame(width: 50, height: 50)
                .previewDisplayName("Triangle • 49mm")
        }
        .padding()
        // .previewLayout(.sizeThatFits)
    }
}
