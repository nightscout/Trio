import SwiftUI

struct CalibrationsChart: View {
    var state: Calibrations.StateModel

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .short
        return formatter
    }

    private let maxValue = 400.0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Rectangle().fill(Color.secondary)
                    .frame(height: geo.size.width)
                Path { path in
                    let size = geo.size.width
                    path.move(
                        to:
                        CGPoint(
                            x: 0,
                            y: size - state.calibrate(0) / maxValue * geo.size.width
                        )
                    )
                    path.addLine(
                        to: CGPoint(
                            x: size,
                            y: size - state.calibrate(Int(maxValue)) / maxValue * geo.size.width
                        )
                    )
                }
                .stroke(.blue, lineWidth: 2)

                ForEach(state.calibrations, id: \.self) { value in
                    ZStack {
                        Circle().fill(.red)
                            .frame(width: 6, height: 6)
                            .position(
                                x: value.x / maxValue * geo.size.width,
                                y: geo.size.width - (value.y / maxValue * geo.size.width)
                            )
                        Text(dateFormatter.string(from: value.date))
                            .foregroundColor(.white)
                            .font(.caption2)
                            .position(
                                x: value.x / maxValue * geo.size.width,
                                y: geo.size.width - (value.y / maxValue * geo.size.width) + 10
                            )
                    }
                }
            }
            .frame(height: geo.size.width)
            .clipped()
        }
    }
}
