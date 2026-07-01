import SwiftUI

/// A reusable animated spinner capsule component that overlays any content
struct CapsuleSpinnerView<Content: View>: View {
    @Environment(\.colorScheme) var colorScheme

    let isLooping: Bool
    let color: Color
    let content: (Bool) -> Content

    @State private var isAnimating: Bool = false
    @State private var dashPhase: CGFloat = 0.0
    @State private var perimeter: CGFloat = 200
    @State private var contentSize: CGSize = .zero
    @State private var animationTask: Task<Void, Never>? = nil

    // OPTION 1: Initializer WITH the animating argument
    init(
        isLooping: Bool,
        color: Color,
        @ViewBuilder content: @escaping (Bool) -> Content
    ) {
        self.isLooping = isLooping
        self.color = color
        self.content = content
    }

    // OPTION 2: Initializer WITHOUT the animating argument
    init(
        isLooping: Bool,
        color: Color,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isLooping = isLooping
        self.color = color
        self.content = { _ in content() }
    }

    var body: some View {
        ZStack {
            // INVISIBLE MEASUREMENT LAYER
            content(isAnimating)
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .hidden()
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear {
                                contentSize = geo.size
                                updatePerimeter(size: geo.size)
                            }
                            .onChange(of: geo.size) { _, newSize in
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    contentSize = newSize
                                    updatePerimeter(size: newSize)
                                }
                            }
                    }
                )

            // VISIBLE ANIMATED LAYER
            content(isAnimating)
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .frame(
                    width: contentSize.width == 0 ? nil : contentSize.width,
                    height: contentSize.height == 0 ? nil : contentSize.height
                )
                .overlay(
                    Group {
                        if isAnimating {
                            Capsule()
                                .stroke(color.opacity(0.4), style: StrokeStyle(
                                    lineWidth: 2.5,
                                    lineCap: .round,
                                    dash: [perimeter * 0.7, perimeter * 0.3],
                                    dashPhase: dashPhase
                                ))
                                .transition(.opacity)
                        } else {
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
        }
        .onAppear {
            updateAnimating(isLooping)
        }
        .onChange(of: isLooping) { _, newValue in
            updateAnimating(newValue)
        }
    }

    private func updatePerimeter(size: CGSize) {
        let w = size.width
        let h = size.height

        if w >= h {
            perimeter = (2 * (w - h) + .pi * h).rounded()
        } else {
            perimeter = (2 * (h - w) + .pi * w).rounded()
        }
    }

    private func updateAnimating(_ newValue: Bool) {
        // Cancel any pending start or stop cycles to prevent overlapping states
        animationTask?.cancel()

        if newValue {
            animationTask = Task {
                // 1. Fade in the spinning capsule state
                withAnimation(.easeInOut(duration: 0.3)) {
                    isAnimating = true
                }

                // 2. Wait exactly for the fade transition to finish mounting the new capsule
                try? await Task.sleep(for: .seconds(0.3))
                guard !Task.isCancelled else { return }

                // 3. Reset the dash structure instantly without animation
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    self.dashPhase = 0.0
                }

                // 4. Safely spin up the loop on the newly mounted capsule view
                withAnimation(.linear(duration: 1.333).repeatForever(autoreverses: false)) {
                    self.dashPhase = -self.perimeter
                }
            }
        } else {
            animationTask = Task {
                // Keep spinning for a minimum timeline requirement if needed, then fade out
                try? await Task.sleep(for: .seconds(2.0))
                guard !Task.isCancelled else { return }

                withAnimation(.easeInOut(duration: 0.3)) {
                    isAnimating = false
                }
            }
        }
    }
}
