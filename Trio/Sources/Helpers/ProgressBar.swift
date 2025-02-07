import SwiftUI

struct ProgressBar: View {
    @Binding var value: Float

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule(style: .circular)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .opacity(0.3)
                    .foregroundColor(.secondary)

                Capsule(style: .circular)
                    .frame(
                        width: min(CGFloat(self.value) * geometry.size.width, geometry.size.width),
                        height: geometry.size.height
                    )
                    .foregroundColor(.accentColor)
                    .animation(.linear, value: value)
            }
        }
        .frame(height: 20)
    }
}
