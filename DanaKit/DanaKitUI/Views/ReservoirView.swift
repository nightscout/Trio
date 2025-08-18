import SwiftUI

struct ReservoirView: View {
    let reservoirLevel: Double
    let fillColor: Color

    // mask height to reservoir height ratio
    let maskHeightRatio = 0.887

    let reservoirAspectRatio = 28.0 / 44.0

    func reservoirSize(in frame: CGSize) -> CGSize {
        let frameAspectRatio = frame.width / frame.height
        if frameAspectRatio > reservoirAspectRatio {
            return CGSize(
                width: frame.height * reservoirAspectRatio,
                height: frame.height
            )
        } else {
            return CGSize(
                width: frame.width,
                height: frame.width / reservoirAspectRatio
            )
        }
    }

    var body: some View {
        ZStack(alignment: Alignment(horizontal: .center, vertical: .center)) {
            GeometryReader { geometry in
                let reservoirSize = reservoirSize(in: geometry.size)
                let frameCenterX = geometry.size.width / 2
                let frameCenterY = geometry.size.height / 2
                let maskHeight = reservoirSize.height * maskHeightRatio
                let fillHeight = maskHeight * (reservoirLevel / 300)
                let maskOffset = (reservoirSize.height - maskHeight) / 2

                Rectangle()
                    .fill(fillColor)
                    .mask(
                        Image(danaImage: "reservoir_mask")
                            .resizable()
                            .scaledToFit()
                            .frame(height: maskHeight)
                            .position(x: frameCenterX, y: frameCenterY + maskOffset)
                    )
                    .mask(
                        Rectangle()
                            .path(in: CGRect(
                                x: 0,
                                y: frameCenterY + maskHeight / 2 - fillHeight + maskOffset,
                                width: geometry.size.width,
                                height: fillHeight
                            ))
                    )
            }
            Image(danaImage: "reservoir")
                .resizable()
                .scaledToFit()
        }
    }
}
