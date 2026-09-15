import SwiftUI

/// Small SF Symbol that visually conveys an alarm's `ActiveOption` window:
/// sun for day-only, moon-and-stars for night-only, overlapped pair for both.
/// The frame is locked to the widest variant (the overlapped pair) so alarm
/// titles don't shift horizontally when alarms with different windows are
/// listed together.
struct AlarmWindowIcon: View {
    let option: ActiveOption

    var body: some View {
        ZStack {
            // Hidden width anchor — always the widest variant. `.hidden()`
            // keeps it in the layout but invisible, so the frame size scales
            // with the caller's font (Dynamic Type-friendly) without
            // hardcoding a width.
            HStack(spacing: -10) {
                Image(systemName: "sun.max.fill")
                Image(systemName: "moon.stars.fill")
            }
            .hidden()

            content
        }
    }

    @ViewBuilder private var content: some View {
        switch option {
        case .day:
            Image(systemName: "sun.max.fill")
                .foregroundStyle(.orange)
        case .night:
            Image(systemName: "moon.stars.fill")
                .foregroundStyle(.indigo)
        case .always:
            HStack(spacing: -10) {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(.orange)
                Image(systemName: "moon.stars.fill")
                    .foregroundStyle(.indigo)
            }
        }
    }
}
