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
    @State private var spinStartDate: Date? = nil
    @State private var startAnimationTask: Task<Void, Never>? = nil
    @State private var stopAnimationTask: Task<Void, Never>? = nil

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
                                // If it was supposed to loop initially, trigger it now that we know the size
                                if isLooping {
                                    updateAnimating(true)
                                }
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
        if newValue {
            stopAnimationTask?.cancel()
            startAnimationTask?.cancel()

            spinStartDate = Date()

            startAnimationTask = Task { @MainActor in
                // 1. Fade in the spinning capsule layout structure FIRST
                //    so the dashed Capsule actually mounts.
                withAnimation(.easeInOut(duration: 0.3)) {
                    isAnimating = true
                }

                // 2. Wait for that transition to finish mounting the new capsule
                try? await Task.sleep(for: .seconds(0.3))
                guard !Task.isCancelled else { return }

                // 3. Reset dashPhase instantly, no animation
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    self.dashPhase = 0.0
                }

                // 4. NOW the dashed Capsule exists — animation will actually attach
                withAnimation(.linear(duration: 1.333).repeatForever(autoreverses: false)) {
                    self.dashPhase = -self.perimeter
                }
            }
        } else {
            stopAnimationTask?.cancel()
            startAnimationTask?.cancel() // keep this symmetric, as discussed earlier

            stopAnimationTask = Task { @MainActor in
                // Enforce minimum 2s total spin time
                let elapsed = spinStartDate.map { Date().timeIntervalSince($0) } ?? 0
                let minimumSpinTime: TimeInterval = 2.0
                let remaining = max(0, minimumSpinTime - elapsed)

                if remaining > 0 {
                    try? await Task.sleep(for: .seconds(remaining))
                    guard !Task.isCancelled else { return }
                }

                // 1. Fade out spinning capsule layout structure
                withAnimation(.easeInOut(duration: 0.3)) {
                    isAnimating = false
                }

                // 2. Wait for the fade transaction to finish unmounting the capsule
                try? await Task.sleep(for: .seconds(0.3))
                guard !Task.isCancelled else { return }

                // 3. Reset spinning animation
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    self.dashPhase = 0.0
                }

                spinStartDate = nil
            }
        }
    }
}
