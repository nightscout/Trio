import SwiftUI

struct WidgetBobble: View {
    @Environment(\.colorScheme) var colorScheme

    let gradient: AngularGradient
    let color: Color

    var body: some View {
        HStack(alignment: .center) {
            ZStack {
                Group {
                    CircleShapeWidget(gradient: gradient)
                    TriangleShapeWidget(color: color)
                }
                CircleShapeWidget(gradient: gradient)
            }
        }
    }
}

struct CircleShapeWidget: View {
    @Environment(\.colorScheme) var colorScheme

    let gradient: AngularGradient

    var body: some View {
//        let colorBackground: Color = colorScheme == .dark ? Color(
//            red: 0.05490196078,
//            green: 0.05490196078,
//            blue: 0.05490196078
//        ) : .white

        Circle()
            .stroke(gradient, lineWidth: 10)
            .background(Circle().fill(.clear))
            .frame(width: 130, height: 130)
    }
}

struct TriangleShapeWidget: View {
    let color: Color

    var body: some View {
        TriangleWidget()
            .fill(color)
            .frame(width: 35, height: 35)
            .rotationEffect(.degrees(90))
            .offset(x: 78)
    }
}

struct TriangleWidget: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let cornerRadius: CGFloat = 2

        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - cornerRadius), control: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()

        return path
    }
}
