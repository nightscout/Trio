import SwiftUI

/// A shimmer/sparkle animation modifier with AI-themed colors (purple/rainbow gradient)
/// Used to indicate an item is being recalculated by AI
struct ShimmerModifier: ViewModifier {
    let isAnimating: Bool

    @State private var phase: CGFloat = 0

    // AI-themed gradient colors (purple to blue to cyan)
    private let gradientColors: [Color] = [
        Color(hue: 0.75, saturation: 0.7, brightness: 1.0).opacity(0.0), // Purple (transparent)
        Color(hue: 0.75, saturation: 0.7, brightness: 1.0).opacity(0.6), // Purple
        Color(hue: 0.65, saturation: 0.8, brightness: 1.0).opacity(0.8), // Blue
        Color(hue: 0.55, saturation: 0.8, brightness: 1.0).opacity(0.6), // Cyan
        Color(hue: 0.55, saturation: 0.8, brightness: 1.0).opacity(0.0) // Cyan (transparent)
    ]

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    if isAnimating {
                        shimmerOverlay(width: geometry.size.width)
                    }
                }
            )
            .animation(.easeInOut(duration: 0.3), value: isAnimating)
            .onChange(of: isAnimating) { animating in
                if animating {
                    startShimmer()
                } else {
                    phase = 0
                }
            }
    }

    private func startShimmer() {
        phase = 0
        DispatchQueue.main.async {
            withAnimation(
                .linear(duration: 1.5)
                    .repeatForever(autoreverses: false)
            ) {
                phase = 1
            }
        }
    }

    private func shimmerOverlay(width: CGFloat) -> some View {
        LinearGradient(
            colors: gradientColors,
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: width * 2)
        .offset(x: -width + (phase * width * 2))
        .mask(
            Rectangle()
        )
        .blendMode(.overlay)
        .onAppear {
            startShimmer()
        }
        .onDisappear {
            phase = 0
        }
    }
}

/// A more prominent shimmer effect for total values
struct TotalShimmerModifier: ViewModifier {
    let isAnimating: Bool

    @State private var phase: CGFloat = 0
    @State private var glowOpacity: Double = 0.5

    // Rainbow gradient similar to the button
    private let rainbowColors: [Color] = [
        Color(hue: 0.75, saturation: 0.7, brightness: 1.0), // Purple
        Color(hue: 0.65, saturation: 0.8, brightness: 1.0), // Blue
        Color(hue: 0.55, saturation: 0.8, brightness: 1.0), // Cyan
        Color(hue: 0.65, saturation: 0.8, brightness: 1.0), // Blue
        Color(hue: 0.75, saturation: 0.7, brightness: 1.0) // Purple
    ]

    func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if isAnimating {
                        // Animated border glow
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                LinearGradient(
                                    colors: rainbowColors,
                                    startPoint: UnitPoint(x: phase, y: 0),
                                    endPoint: UnitPoint(x: phase + 0.5, y: 1)
                                ),
                                lineWidth: 2
                            )
                            .blur(radius: 2)
                            .opacity(glowOpacity)
                    }
                }
            )
            .onChange(of: isAnimating) { animating in
                if animating {
                    startAnimation()
                } else {
                    phase = 0
                    glowOpacity = 0.5
                }
            }
            .onAppear {
                if isAnimating {
                    startAnimation()
                }
            }
    }

    private func startAnimation() {
        phase = 0
        glowOpacity = 0.5
        DispatchQueue.main.async {
            withAnimation(
                .linear(duration: 2)
                    .repeatForever(autoreverses: false)
            ) {
                phase = 1
            }
            withAnimation(
                .easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true)
            ) {
                glowOpacity = 1.0
            }
        }
    }
}

// MARK: - View Extensions

extension View {
    /// Applies the AI shimmer animation to indicate recalculation
    func shimmer(isAnimating: Bool) -> some View {
        modifier(ShimmerModifier(isAnimating: isAnimating))
    }

    /// Applies a more prominent shimmer for total values
    func totalShimmer(isAnimating: Bool) -> some View {
        modifier(TotalShimmerModifier(isAnimating: isAnimating))
    }
}

// MARK: - Sparkle Icon Animation

/// An animated sparkle icon for AI features
struct AnimatedSparkleIcon: View {
    let isAnimating: Bool

    @State private var scale: CGFloat = 1.0
    @State private var rotation: Double = 0
    @State private var opacity: Double = 1.0

    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color(hue: 0.75, saturation: 0.7, brightness: 1.0),
                        Color(hue: 0.55, saturation: 0.8, brightness: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .scaleEffect(scale)
            .rotationEffect(.degrees(rotation))
            .opacity(opacity)
            .onChange(of: isAnimating) { animating in
                if animating {
                    startAnimation()
                } else {
                    stopAnimation()
                }
            }
            .onAppear {
                if isAnimating {
                    startAnimation()
                }
            }
    }

    private func startAnimation() {
        withAnimation(
            .easeInOut(duration: 0.6)
                .repeatForever(autoreverses: true)
        ) {
            scale = 1.2
            opacity = 0.7
        }
        withAnimation(
            .linear(duration: 3)
                .repeatForever(autoreverses: false)
        ) {
            rotation = 360
        }
    }

    private func stopAnimation() {
        withAnimation(.easeOut(duration: 0.3)) {
            scale = 1.0
            opacity = 1.0
        }
        rotation = 0
    }
}

#if DEBUG
    struct ShimmerModifier_Previews: PreviewProvider {
        static var previews: some View {
            VStack(spacing: 20) {
                Text("32g")
                    .font(.body.monospacedDigit())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.secondarySystemFill))
                    .cornerRadius(6)
                    .shimmer(isAnimating: true)

                Text("Total: 47g")
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemFill))
                    .cornerRadius(8)
                    .totalShimmer(isAnimating: true)

                HStack {
                    AnimatedSparkleIcon(isAnimating: true)
                    Text("Recalculating...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
    }
#endif
