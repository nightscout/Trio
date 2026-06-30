import SwiftUI

struct SlideToConfirmView: View {
    let label: String
    let isEnabled: Bool
    let action: () -> Void

    @State private var dragOffset: CGFloat = 0

    private let thumbSize: CGFloat = 52
    private let trackHeight: CGFloat = 56
    private let completionThreshold: CGFloat = 0.85

    var body: some View {
        GeometryReader { geo in
            let maxDrag = geo.size.width - thumbSize - 8
            let progress = maxDrag > 0 ? dragOffset / maxDrag : 0

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(isEnabled ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.2))

                Text(label)
                    .font(.headline)
                    .foregroundStyle(isEnabled ? .white.opacity(1 - progress) : .secondary)
                    .frame(maxWidth: .infinity)

                RoundedRectangle(cornerRadius: thumbSize / 2)
                    .fill(isEnabled ? Color.accentColor : Color.secondary.opacity(0.4))
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay {
                        Image(systemName: "chevron.right.2")
                            .foregroundStyle(.white)
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .offset(x: 4 + dragOffset)
                    .gesture(
                        isEnabled ? DragGesture()
                            .onChanged { value in
                                dragOffset = min(max(0, value.translation.width), maxDrag)
                            }
                            .onEnded { _ in
                                guard maxDrag > 0 else { return }
                                if dragOffset >= maxDrag * completionThreshold {
                                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                                    action()
                                } else {
                                    withAnimation(.spring()) { dragOffset = 0 }
                                }
                            } : nil
                    )
            }
            .frame(height: trackHeight)
        }
        .frame(height: trackHeight)
    }
}
