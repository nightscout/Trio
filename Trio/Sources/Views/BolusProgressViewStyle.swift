import SwiftUI

public struct BolusProgressViewStyle: ProgressViewStyle {
    public func makeBody(configuration: LinearProgressViewStyle.Configuration) -> some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 4.0)
                .opacity(0.3)
                .foregroundColor(.secondary)
                .frame(width: 22, height: 22)

            Rectangle().fill(Color.insulin)
                .frame(width: 8, height: 8)

            Circle()
                .trim(from: 0.0, to: CGFloat(configuration.fractionCompleted ?? 0))
                .stroke(style: StrokeStyle(lineWidth: 4.0, lineCap: .butt, lineJoin: .round))
                .foregroundColor(.insulin)
                .rotationEffect(Angle(degrees: -90))
                .frame(width: 22, height: 22)
        }.frame(width: 30, height: 30)
    }
}
