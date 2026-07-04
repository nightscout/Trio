import LoopKit
import LoopKitUI
import SwiftUI

/// Concentric outer ring around the glucose bobble that drains clockwise from
/// 12 o'clock as the sensor session ages. Always renders a faint track behind
/// the fill so the indicator's footprint is visible even at `progress == 0`.
struct SensorLifecycleArcView: View {
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
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(arcColor, style: StrokeStyle(lineWidth: Self.strokeWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.25), value: progress)
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .allowsHitTesting(false)
    }
}

#Preview("Arc — progress states") {
    VStack(spacing: 24) {
        SensorLifecycleArcView(progress: 0.15, progressState: .normalCGM)
        SensorLifecycleArcView(progress: 0.55, progressState: .normalCGM)
        SensorLifecycleArcView(progress: 0.92, progressState: .warning)
        SensorLifecycleArcView(progress: 1.0, progressState: .critical)
    }
    .padding(40)
    .background(Color.black)
    .preferredColorScheme(.dark)
}
