import SwiftUI

struct Triangle: Shape {
    /// Creates a triangle shape pointing to the right
    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Draw the triangle pointing to the right
        path.move(to: CGPoint(x: rect.maxX - 10, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY),
            control: CGPoint(x: rect.midX - 15, y: rect.midY)
        )
        path.closeSubpath()

        return path
    }
}

/// A view that displays a circular trend indicator with a directional triangle
struct TrendShape: View {
    /// Rotation angle in degrees for the trend direction
    let rotationDegrees: Double

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

    var body: some View {
        ZStack {
            // Outer circle with gradient
            Circle()
                .stroke(angularGradient, lineWidth: 6)
                .frame(width: 90, height: 90)
                .background(Circle().fill(Color.black))

            // Triangle with the color of the last gradient color
            Triangle()
                .fill(triangleColor)
                .frame(width: 20, height: 20)
                .offset(x: 55)
        }
        .rotationEffect(.degrees(rotationDegrees))
        .shadow(color: Color.black.opacity(0.33), radius: 3)
    }
}
