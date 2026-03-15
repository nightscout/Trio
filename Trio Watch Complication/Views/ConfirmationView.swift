import SwiftUI

struct ConfirmationView: View {
    @Binding var success: Bool?

    var body: some View {
        ZStack {
            Group {
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .foregroundColor(.loopGreen)
                    .opacity(success == true ? 1.0 : 0.0)
                    .scaleEffect(success == true ? 1.0 : 0.0)

                Image(systemName: "xmark.circle.fill")
                    .resizable()
                    .foregroundColor(.loopRed)
                    .opacity(success == false ? 1.0 : 0.0)
                    .scaleEffect(success == false ? 1.0 : 0.0)

                BlinkingView(count: 10, size: 10)
                    .opacity(success == nil ? 1.0 : 0.0)
                    .scaleEffect(success == nil ? 1.0 : 0.0)
            }
            .frame(width: 50, height: 50)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ConfirmationView_Previews: PreviewProvider {
    struct Container: View {
        @State var success: Bool?

        var body: some View {
            ConfirmationView(success: $success)
        }
    }

    static var previews: some View {
        Container()
    }
}

struct BlinkingView: View {
    let count: UInt
    let size: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ForEach(0 ..< Int(count)) { index in
                item(forIndex: index, in: geometry.size)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .animation(.none, value: false)
        .aspectRatio(contentMode: .fit)
        .onAppear {
            scale = 1
            opacity = 1
        }
    }

    @State var scale = 0.5
    @State var opacity = 0.25

    func animation(index: Int) -> Animation {
        Animation
            .default
            .repeatCount(.max, autoreverses: true)
            .delay(Double(index) / Double(count) / 2)
    }

    private func item(forIndex index: Int, in geometrySize: CGSize) -> some View {
        let angle = 2 * CGFloat.pi / CGFloat(count) * CGFloat(index)
        let x = (geometrySize.width / 2 - size / 2) * cos(angle)
        let y = (geometrySize.height / 2 - size / 2) * sin(angle)
        return Circle()
            .frame(width: size, height: size)
            .scaleEffect(scale)
            .opacity(opacity)
            .animation(animation(index: index), value: scale)
            .animation(animation(index: index), value: opacity)
            .offset(x: x, y: y)
    }
}
