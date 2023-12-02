import SwiftUI

struct WidgetBobble: View {
    @Environment(\.colorScheme) var colorScheme

    let gradient: AngularGradient
    let color: Color

    var body: some View {
        HStack(alignment: .center) {
            ZStack {
                Group {
                    CircleShape(gradient: gradient)
                    TriangleShape(color: color)
                }.shadow(color: Color.black.opacity(colorScheme == .dark ? 0.75 : 0.33), radius: colorScheme == .dark ? 5 : 3)
                CircleShape(gradient: gradient)
            }
        }
    }
}

struct CircleShape: View {
    @Environment(\.colorScheme) var colorScheme

    let gradient: AngularGradient

    var body: some View {
        let colorBackground: Color = colorScheme == .dark ? Color(
            red: 0.05490196078,
            green: 0.05490196078,
            blue: 0.05490196078
        ) : .white

        Circle()
            .stroke(gradient, lineWidth: 6)
            .background(Circle().fill(colorBackground))
            .frame(width: 130, height: 130)
    }
}

struct TriangleShape: View {
    let color: Color

    var body: some View {
        Triangle()
            .fill(color)
            .frame(width: 35, height: 35)
            .rotationEffect(.degrees(90))
            .offset(x: 70)
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let cornerRadius: CGFloat = 8

        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - cornerRadius), control: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()

        return path
    }
}
