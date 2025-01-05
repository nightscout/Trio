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
                Circle()
                    // TODO: set loop colors conditionally, not hard coded
                    .stroke(Color.green, lineWidth: is40mm ? 1 : 1.5)
                    .frame(width: is40mm ? 86 : 105, height: is40mm ? 86 : 105)
                    .background(Circle().fill(Color.bgDarkBlue))
                    // TODO: set loop colors conditionally, not hard coded
                    .shadow(color: .green, radius: is40mm ? 8 : 12)

                TrendShape(rotationDegrees: rotationDegrees, isSmallDevice: is40mm)
                    .animation(.spring(response: 0.5, dampingFraction: 0.6), value: rotationDegrees)
                    .shadow(color: Color.black.opacity(0.5), radius: 5)

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

//            Spacer()

            Text(state.lastLoopTime ?? "--").font(.system(size: is40mm ? 9 : 10))

            Spacer()

        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
