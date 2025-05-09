import SwiftUI

struct LogoBurstSplash<Content: View>: View {
    @Binding var isActive: Bool
    private let content: Content

    @State private var logoScale: CGFloat = 0.5
    @State private var logoOpacity: Double = 0
    @State private var logoRotation: Double = 0
    @State private var isPulsing = false

    @State private var exploded = false
    @State private var shapes: [BurstShape] = []
    @State private var shapesOpacity: Double = 1

    @State private var viewOpacity: Double = 1.0
    @State private var splashScale: CGFloat = 1.0

    init(isActive: Binding<Bool>, @ViewBuilder content: () -> Content) {
        _isActive = isActive
        self.content = content()
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                content
                    .opacity(isActive ? 0 : 1)

                if isActive {
                    LinearGradient(
                        gradient: Gradient(colors: [Color.bgDarkBlue, Color.bgDarkerDarkBlue]),
                        startPoint: .top, endPoint: .bottom
                    )
                    .ignoresSafeArea()

                    ZStack {
                        // shards
                        ForEach(shapes) { shape in
                            Circle()
                                .fill(shape.color)
                                .frame(width: 6, height: 6)
                                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                                .offset(
                                    x: exploded ? shape.xOffset : 0,
                                    y: exploded ? shape.yOffset : 0
                                )
                                .opacity(exploded ? shapesOpacity : 0)
                                .animation(.easeOut(duration: 0.8), value: exploded)
                                .animation(.easeIn(duration: 0.5), value: shapesOpacity)
                        }

                        // logo
                        Image("trioCircledNoBackground")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100, height: 100)
                            .scaleEffect(isPulsing ? 1.1 : logoScale)
                            .opacity(logoOpacity)
                            .rotationEffect(.degrees(logoRotation))
                            .animation(.easeInOut(duration: 1.0), value: logoScale)
                            .animation(.easeInOut(duration: 1.0), value: logoOpacity)
                            .animation(.linear(duration: 2.0), value: logoRotation)
                            .animation(
                                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                                value: isPulsing
                            )
                    }
                    .scaleEffect(splashScale)
                    .opacity(viewOpacity)
                    .onAppear {
                        shapes = BurstShape.createBurst(count: 250, in: geo.frame(in: .local))

                        withAnimation {
                            isPulsing = true
                            logoOpacity = 1
                            logoScale = 1
                            logoRotation = 360
                        }

                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            isPulsing = false
                        }

                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            exploded = true
                        }

                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation {
                                logoOpacity = 0
                                shapesOpacity = 0
                            }
                        }

                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
                            withAnimation(.easeIn(duration: 0.6)) {
                                viewOpacity = 0
                                splashScale = 0.1
                            }
                        }

                        // 5) Hide splash at 3.0s
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.1) {
                            isActive = false
                        }
                    }
                }
            }
        }
    }
}

private struct BurstShape: Identifiable {
    let id = UUID()
    let angle: Double
    let distance: CGFloat
    let color: Color

    var xOffset: CGFloat { cos(angle) * distance }
    var yOffset: CGFloat { sin(angle) * distance }

    static func createBurst(count: Int, in rect: CGRect) -> [BurstShape] {
        let gradientColors: [Color] = [
            Color(red: 0.7216, green: 0.3412, blue: 1),
            Color(red: 0.6235, green: 0.4235, blue: 0.9804),
            Color(red: 0.4863, green: 0.5451, blue: 0.9529),
            Color(red: 0.3412, green: 0.6667, blue: 0.9255),
            Color(red: 0.2627, green: 0.7333, blue: 0.9137)
        ]
        return (0 ..< count).map { i in
            let angle = Double.random(in: 0 ..< 360) * .pi / 180
            let distance = CGFloat.random(
                in: min(rect.width, rect.height) * 0.3 ... max(rect.width, rect.height) * 0.6
            )
            let color = gradientColors[i % gradientColors.count]
            return BurstShape(angle: angle, distance: distance, color: color)
        }
    }
}

// MARK: Preview

struct LogoBurstSplash_Previews: PreviewProvider {
    static var previews: some View {
        LogoBurstSplash(isActive: .constant(true)) {
            ZStack {
                Color.white.ignoresSafeArea()
                Text("Main Content")
                    .font(.largeTitle)
                    .foregroundColor(.gray)
            }
        }
        .previewDevice("iPhone 14 Pro")
    }
}
