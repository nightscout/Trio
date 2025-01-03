import SwiftUI

struct GlucoseTrendView: View {
    let state: WatchState
    let rotationDegrees: Double

    private var is40mm: Bool {
        let size = WKInterfaceDevice.current().screenBounds.size
        return size.height < 225 && size.width < 185
    }

    var body: some View {
        VStack {
            ZStack {
                TrendShape(rotationDegrees: rotationDegrees, isSmallDevice: is40mm)
                    .animation(.spring(response: 0.5, dampingFraction: 0.6), value: rotationDegrees)
                    // TODO: set loop colors conditionally, not hard coded
                    .shadow(color: .green, radius: is40mm ? 8 : 12)

                VStack(alignment: .center) {
                    Text(state.currentGlucose)
                        .fontWeight(.semibold)
                        .font(.system(is40mm ? .title2 : .title, design: .rounded))

                    if let delta = state.delta {
                        Text(delta)
                            .fontWeight(.semibold)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Text(state.lastLoopTime ?? "--").font(is40mm ? .footnote : .caption)

            Spacer()

        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
