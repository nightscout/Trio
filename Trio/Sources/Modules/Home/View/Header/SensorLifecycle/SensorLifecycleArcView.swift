import LoopKit
import LoopKitUI
import SwiftUI

/// Concentric outer ring around the glucose bobble that counts down: the arc
/// starts full and drains back toward 12 o'clock as the phase elapses, since
/// warmup, grace period, and lifetime are all countdowns. A faint track stays
/// behind the arc so the footprint remains visible when nearly depleted.
struct SensorLifecycleArcView: View {
    /// Elapsed fraction of the lifecycle phase (LoopKit `percentComplete`).
    let progress: Double
    let progressState: DeviceLifecycleProgressState

    /// Outer diameter — bobble is ~130pt; arc sits 10pt outside the ring stroke.
    static let diameter: CGFloat = 146
    static let strokeWidth: CGFloat = 4

    private var arcColor: Color {
        switch progressState {
        case .critical:
            return Color.loopRed
        case .warning:
            return Color.orange
        case .dimmed,
             .normalCGM,
             .normalPump:
            return Color.loopGreen
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.4), lineWidth: Self.strokeWidth)

            Circle()
                .trim(from: 0, to: 1 - max(0, min(1, progress)))
                .stroke(arcColor, style: StrokeStyle(lineWidth: Self.strokeWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // mirror: the arc extends counterclockwise and drains back into 12 o'clock
                .scaleEffect(x: -1)
                .animation(.easeInOut(duration: 0.25), value: progress)
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .allowsHitTesting(false)
    }
}

#Preview("Arc — progress states") {
    VStack(spacing: 24) {
        SensorLifecycleArcView(progress: 0.15, progressState: .normalCGM) // nearly full
        SensorLifecycleArcView(progress: 0.55, progressState: .normalCGM)
        SensorLifecycleArcView(progress: 0.92, progressState: .warning) // almost drained
        SensorLifecycleArcView(progress: 1.0, progressState: .critical) // track only
    }
    .padding(40)
    .background(Color.black)
    .preferredColorScheme(.dark)
}
