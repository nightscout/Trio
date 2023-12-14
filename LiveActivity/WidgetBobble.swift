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
            .offset(x: 88)
    }
}

struct TriangleWidget: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: rect.midX, y: rect.minY + 15))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.midY + 10))
        path.closeSubpath()

        return path
    }
}
