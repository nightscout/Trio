import SwiftUI

/// A reusable animated spinner capsule component that overlays any content
struct SpinnerView<Content: View>: View {
    @Environment(\.colorScheme) var colorScheme

    let isLooping: Bool
    let color: Color
    let content: Content

    @State private var isAnimatingLoop: Bool = false
    @State private var dashPhase: CGFloat = 0.0
    @State private var perimeter: CGFloat = 200
    @State private var stopAnimationTask: Task<Void, Never>? = nil

    init(
        isLooping: Bool,
        color: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.isLooping = isLooping
        self.color = color
        self.content = content()
    }

    var body: some View {
        content
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(
                GeometryReader { geo in
                    Color.clear.onAppear {
                        updatePerimeter(size: geo.size)
                    }
                    .onChange(of: geo.size) { _, newSize in
                        updatePerimeter(size: newSize)
                    }
                }
            )
            .overlay(
                Group {
                    if isAnimatingLoop {
                        // Animated spinning pill
                        Capsule()
                            .stroke(color.opacity(0.4), style: StrokeStyle(
                                lineWidth: 2.5,
                                lineCap: .round,
                                dash: [perimeter * 0.7, perimeter * 0.3],
                                dashPhase: dashPhase
                            ))
                            .transition(.opacity)
                    } else {
                        // Static pill
                        Capsule()
                            .stroke(color.opacity(0.4), style: StrokeStyle(
                                lineWidth: 2,
                                lineCap: .round,
                                dash: [perimeter + 10, 0]
                            ))
                            .transition(.opacity)
                    }
                }
            )
            .onAppear {
                updateAnimating(isLooping)
            }
            .onChange(of: isLooping) {
                updateAnimating(isLooping)
            }
    }

    private func updatePerimeter(size: CGSize) {
        let w = size.width
        let h = size.height

        // Capsule perimeter = (2 × straight segments) + (π × diameter)
        if w >= h {
            perimeter = (2 * (w - h) + .pi * h).rounded()
        } else {
            perimeter = (2 * (h - w) + .pi * w).rounded()
        }
    }

    private func updateAnimating(_ newValue: Bool) {
        if newValue {
            // Show the spinner
            withAnimation(.easeInOut(duration: 0.3)) {
                isAnimatingLoop = true
            }

            // Start dash rotation after view appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // Reset phase without animation
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    self.dashPhase = 0.0
                }

                // Then animate it smoothly
                withAnimation(.linear(duration: 1.333).repeatForever(autoreverses: false)) {
                    self.dashPhase = -self.perimeter
                }
            }
        } else {
            // Let spinner continue for 2 seconds, then fade to static pill
            stopAnimationTask?.cancel()
            stopAnimationTask = Task {
                try? await Task.sleep(for: .seconds(2.0))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isAnimatingLoop = false
                    }
                }
            }
        }
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 20) {
        SpinnerView(isLooping: true, color: .green) {
            HStack(alignment: .center) {
                Image(systemName: "circle.and.line.horizontal")
                    .symbolEffect(.pulse, options: .repeating, isActive: true)
                Text(verbatim: "looping")
            }
            .font(.callout).fontWeight(.bold).fontDesign(.rounded)
            .foregroundColor(.green)
        }

        SpinnerView(isLooping: false, color: .orange) {
            HStack(alignment: .center) {
                Image(systemName: "circle")
                Text("5 min ago")
            }
            .font(.callout).fontWeight(.bold).fontDesign(.rounded)
            .foregroundColor(.orange)
        }
    }
    .padding()
}
