import CoreData
import SwiftDate
import SwiftUI
import UIKit

struct LoopView: View {
    @Environment(\.colorScheme) var colorScheme

    private enum Config {
        static let lag: TimeInterval = 30
    }

    let closedLoop: Bool
    let timerDate: Date
    let isLooping: Bool
    let lastLoopDate: Date
    let manualTempBasal: Bool

    let determination: [OrefDetermination]

    private let rect = CGRect(x: 0, y: 0, width: 18, height: 18)

    @State private var isAnimatingLoop: Bool = false
    @State private var dashPhase: CGFloat = 0.0
    @State private var perimeter: CGFloat = 200
    @State private var stopAnimationTask: Task<Void, Never>? = nil

    var body: some View {
        loopStatusWithMinutes
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
                                lineWidth: isAnimatingLoop ? 2.5 : 2,
                                lineCap: .round,
                                dash: [perimeter * 0.7, perimeter * 0.3],
                                dashPhase: dashPhase
                            ))
                            .transition(.opacity)
                    } else {
                        // Static pill
                        Capsule()
                            .stroke(color.opacity(0.4), style: StrokeStyle(
                                lineWidth: isAnimatingLoop ? 2.5 : 2,
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

    private var loopStatusWithMinutes: some View {
        HStack(alignment: .center) {
            ZStack {
                Image(systemName: (!closedLoop || manualTempBasal) ? "circle.and.line.horizontal" : "circle")
                    .symbolEffect(.pulse, options: .repeating, isActive: isAnimatingLoop)
            }
            if isAnimatingLoop {
                // Exclude from localization; the term 'looping' is an idiom in the DIY loop jargon. IYKYK
                Text(verbatim: "looping")
            } else if manualTempBasal {
                Text("Manual")
            } else if determination.first?
                .deliverAt !=
                nil
            {
                // previously the .timestamp property was used here because this only gets updated when the reportenacted function in the aps manager gets called
                Text(timeString)
            } else {
                Text("--")
            }
        }
        .font(.callout).fontWeight(.bold).fontDesign(.rounded)
        .foregroundColor(color)
    }

    private var timeString: String {
        let minutesAgo = TimeAgoFormatter.minutesAgoValue(from: lastLoopDate)
        if minutesAgo > 1440 {
            return "--"
        } else {
            return TimeAgoFormatter.minutesAgo(from: lastLoopDate)
        }
    }

    private var color: Color {
        guard determination.first?.timestamp != nil
        else {
            // previously the .timestamp property was used here because this only gets updated when the reportenacted function in the aps manager gets called
            return .secondary
        }
        guard manualTempBasal == false else {
            return .loopManualTemp
        }
        guard closedLoop == true else {
            return .secondary
        }

        let delta = timerDate.timeIntervalSince(lastLoopDate) - Config.lag

        if delta <= 5.minutes.timeInterval {
            guard determination.first?.timestamp != nil else {
                return .loopYellow
            }
            return .loopGreen
        } else if delta <= 10.minutes.timeInterval {
            return .loopYellow
        } else {
            return .loopRed
        }
    }
}

extension View {
    func animateForever(
        using animation: Animation = Animation.easeInOut(duration: 1),
        autoreverses: Bool = false,
        _ action: @escaping () -> Void
    ) -> some View {
        let repeated = animation.repeatForever(autoreverses: autoreverses)

        return onAppear {
            withAnimation(repeated) {
                action()
            }
        }
    }
}
