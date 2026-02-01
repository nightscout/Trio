import SwiftUI
import UIKit

/// An animated button with a purple/blue AI-themed gradient border,
/// designed for AI-related features with a modern, magical appearance.
struct AnimatedRainbowButton: View {
    let title: String
    let icon: String
    let isLoading: Bool
    let action: () -> Void

    @State private var rotation: Double = 0
    @State private var isAnimating = false
    @State private var introGlow: Double = 1.0
    @State private var glowOpacity: Double = 0.5
    @State private var effectsOpacity: Double = 1.0

    // Purple/blue AI-themed gradient colors
    private let glowColors: [Color] = [
        Color(hue: 0.75, saturation: 0.7, brightness: 1.0), // Purple
        Color(hue: 0.60, saturation: 0.7, brightness: 1.0), // Blue
        Color(hue: 0.55, saturation: 0.6, brightness: 1.0), // Cyan
        Color(hue: 0.65, saturation: 0.8, brightness: 1.0), // Blue
        Color(hue: 0.80, saturation: 0.6, brightness: 1.0), // Violet
        Color(hue: 0.75, saturation: 0.7, brightness: 1.0) // Purple (loop)
    ]

    init(
        title: String,
        icon: String = "sparkles",
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Animated gradient border
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        AngularGradient(
                            colors: glowColors,
                            center: .center,
                            angle: .degrees(rotation)
                        ),
                        lineWidth: 2.5
                    )
                    .blur(radius: 0.5)
                    .opacity(effectsOpacity)

                // Glow effect behind the border
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        AngularGradient(
                            colors: glowColors,
                            center: .center,
                            angle: .degrees(rotation)
                        ),
                        lineWidth: 4 + (introGlow * 4)
                    )
                    .blur(radius: 6 + (introGlow * 6))
                    .opacity((glowOpacity + (introGlow * 0.4)) * effectsOpacity)

                // Clear background with slight tint
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(UIColor.systemBackground).opacity(0.95))

                // Static border that shows when effects fade
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(1.0 - effectsOpacity), lineWidth: 1.0)

                // Button content
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .medium))
                    }

                    Text(title)
                        .bold()
                }
                .foregroundColor(effectsOpacity > 0.01 && introGlow > 0.01 ? Color(
                    hue: 0.70,
                    saturation: 0.6 * introGlow * effectsOpacity,
                    brightness: 0.5 + (0.3 * introGlow * effectsOpacity)
                ) : .primary)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
        }
        .disabled(isLoading)
        .opacity(isLoading ? 0.7 : 1.0)
        .onAppear {
            startAnimation()
            // Fade out all rainbow/glow effects after 4 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 1.5)) {
                    introGlow = 0
                    effectsOpacity = 0
                }
            }
        }
    }

    private func startAnimation() {
        guard !isAnimating else { return }
        isAnimating = true

        withAnimation(
            .linear(duration: 3)
                .repeatForever(autoreverses: false)
        ) {
            rotation = 360
        }
        withAnimation(
            .easeInOut(duration: 0.8)
                .repeatForever(autoreverses: true)
        ) {
            glowOpacity = 0.7
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        AnimatedRainbowButton(
            title: "Analyze Food with AI",
            icon: "sparkles",
            isLoading: false,
            action: {}
        )
        .padding(.horizontal)

        AnimatedRainbowButton(
            title: "Analyzing...",
            icon: "sparkles",
            isLoading: true,
            action: {}
        )
        .padding(.horizontal)
    }
    .padding(.vertical)
    .background(Color(UIColor.systemGroupedBackground))
}
