import Foundation
import SwiftUI

struct ContactPicture: View {
    private enum Config {
        static let lag: TimeInterval = 30
    }

    @Binding var contact: ContactTrickEntry
    @Binding var state: ContactTrickState

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func getImage(
        contact: ContactTrickEntry,
        state: ContactTrickState
    ) -> UIImage {
        let width = 1024.0
        let height = 1024.0
        var rect = CGRect(x: 0, y: 0, width: width, height: height)
        let textColor: Color = contact.darkMode ?
            Color(red: 250 / 256, green: 250 / 256, blue: 250 / 256) :
            Color(red: 20 / 256, green: 20 / 256, blue: 20 / 256)
        let secondaryTextColor: Color = contact.darkMode ?
            Color(red: 220 / 256, green: 220 / 256, blue: 220 / 256) :
            Color(red: 40 / 256, green: 40 / 256, blue: 40 / 256)
        let fontWeight = contact.fontWeight.toUI()

        UIGraphicsBeginImageContext(rect.size)
        if let context = UIGraphicsGetCurrentContext() {
            context.setShouldAntialias(true)
            context.setAllowsAntialiasing(true)
        }

        let ringWidth = Double(contact.ringWidth) / 100.0
        let ringGap = Double(contact.ringGap) / 100.0
        let outerGap = 0.03

        if contact.ring1 != .none {
            rect = CGRect(
                x: rect.minX + width * outerGap,
                y: rect.minY + height * outerGap,
                width: rect.width - width * outerGap * 2,
                height: rect.height - height * outerGap * 2
            )

            let ringRect = CGRect(
                x: rect.minX + width * ringWidth * 0.5,
                y: rect.minY + height * ringWidth * 0.5,
                width: rect.width - width * ringWidth,
                height: rect.height - height * ringWidth
            )

            drawRing(ring: contact.ring1, contact: contact, state: state, rect: ringRect, strokeWidth: width * ringWidth)

            rect = CGRect(
                x: rect.minX + width * (ringWidth + ringGap),
                y: rect.minY + height * (ringWidth + ringGap),
                width: rect.width - width * (ringWidth + ringGap) * 2,
                height: rect.height - height * (ringWidth + ringGap) * 2
            )
        }

        switch contact.layout {
        case .single:
            let showTop = contact.top != .none
            let showBottom = contact.bottom != .none

            let centerX = rect.minX + rect.width / 2
            let centerY = rect.minY + rect.height / 2
            let radius = min(rect.width, rect.height) / 2

            var primaryHeight = radius * 0.8
            let topHeight = radius * 0.5
            var bottomHeight = radius * 0.5

            var primaryY = centerY - primaryHeight / 2

            if contact.bottom == .none, contact.top != .none {
                primaryY += radius * 0.2
            }
            if contact.bottom != .none, contact.top == .none {
                primaryY -= radius * 0.2
            }

            let topY = primaryY - topHeight
            var bottomY = primaryY + primaryHeight

            let primaryWidth = 2 * sqrt(radius * radius - (primaryHeight * 0.5) * (primaryHeight * 0.5))
            let topWidth = 2 *
                sqrt(radius * radius - (topHeight + primaryHeight * 0.5) * (topHeight + primaryHeight * 0.5))
            var bottomWidth = 2 *
                sqrt(radius * radius - (bottomHeight + primaryHeight * 0.5) * (bottomHeight + primaryHeight * 0.5))

            if contact.bottom != .none, contact.top == .none {
                // move things around a little bit to give more space to the bottom area
                if contact.ring1 == .iob || contact.ring1 == .cob || contact.ring1 == .iobcob ||
                    (contact.bottom == .trend && contact.ring1 == .loop)
                {
                    bottomHeight = bottomHeight + height * ringWidth * 2
                    bottomWidth = bottomWidth + width * ringWidth * 2
                } else if contact.ring1 == .loop {
                    primaryHeight = primaryHeight - height * ringWidth
                    bottomY = primaryY + primaryHeight
                    bottomHeight = bottomHeight + height * ringWidth * 2
                    bottomWidth = bottomWidth + width * ringWidth * 2
                }
            }

            let primaryRect = (showTop || showBottom) ? CGRect(
                x: centerX - primaryWidth * 0.5,
                y: primaryY,
                width: primaryWidth,
                height: primaryHeight
            ) : rect
            let topRect = CGRect(
                x: centerX - topWidth * 0.5,
                y: topY,
                width: topWidth,
                height: topHeight
            )
            let bottomRect = CGRect(
                x: centerX - bottomWidth * 0.5,
                y: bottomY,
                width: bottomWidth,
                height: bottomHeight
            )
            let secondaryFontSize = contact.secondaryFontSize

            displayPiece(
                value: contact.primary,
                contact: contact,
                state: state,
                rect: primaryRect,
                fitHeigh: false,
                fontName: contact.fontName,
                fontSize: contact.fontSize,
                fontWeight: fontWeight,
                fontTracking: contact.fontTracking,
                color: textColor
            )
            if showTop {
                displayPiece(
                    value: contact.top,
                    contact: contact,
                    state: state,
                    rect: topRect,
                    fitHeigh: true,
                    fontName: contact.fontName,
                    fontSize: secondaryFontSize,
                    fontWeight: fontWeight,
                    fontTracking: contact.fontTracking,
                    color: secondaryTextColor
                )
            }
            if showBottom {
                displayPiece(
                    value: contact.bottom,
                    contact: contact,
                    state: state,
                    rect: bottomRect,
                    fitHeigh: true,
                    fontName: contact.fontName,
                    fontSize: secondaryFontSize,
                    fontWeight: fontWeight,
                    fontTracking: contact.fontTracking,
                    color: secondaryTextColor
                )
            }

        case .split:
            let centerX = rect.origin.x + rect.size.width / 2
            let centerY = rect.origin.y + rect.size.height / 2
            let radius = min(rect.size.width, rect.size.height) / 2

            let rectangleHeight = radius * sqrt(2) / 2
            let rectangleWidth = sqrt(2) * radius

            let topY = centerY - rectangleHeight
            let bottomY = centerY

            let topRect = CGRect(
                x: centerX - rectangleWidth / 2,
                y: topY,
                width: rectangleWidth,
                height: rectangleHeight
            )
            let bottomRect = CGRect(
                x: centerX - rectangleWidth / 2,
                y: bottomY,
                width: rectangleWidth,
                height: rectangleHeight
            )
            let topFontSize = contact.fontSize
            let bottomFontSize = contact.secondaryFontSize

            displayPiece(
                value: contact.top,
                contact: contact,
                state: state,
                rect: topRect,
                fitHeigh: true,
                fontName: contact.fontName,
                fontSize: topFontSize,
                fontWeight: fontWeight,
                fontTracking: contact.fontTracking,
                color: textColor
            )
            displayPiece(
                value: contact.bottom,
                contact: contact,
                state: state,
                rect: bottomRect,
                fitHeigh: true,
                fontName: contact.fontName,
                fontSize: bottomFontSize,
                fontWeight: fontWeight,
                fontTracking: contact.fontTracking,
                color: textColor
            )
        }
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image ?? UIImage()
    }

    private static func displayPiece(
        value: ContactTrickValue,
        contact: ContactTrickEntry,
        state: ContactTrickState,
        rect: CGRect,
        fitHeigh: Bool,
        fontName: String?,
        fontSize: Int,
        fontWeight: UIFont.Weight,
        fontTracking: FontTracking,
        color: Color
    ) {
//        guard let context = UIGraphicsGetCurrentContext() else {
//            return
//        }
//
//        // Set the fill color (optional)
//        context.setFillColor(UIColor.red.cgColor)
//
//        // Set the stroke color (optional)
//        context.setStrokeColor(UIColor.black.cgColor)
//
//        // Set the line width (optional)
//        context.setLineWidth(2.0)
//
//        // Create a rectangle
//        let rectangle = CGRect(x: 50, y: 50, width: 100, height: 100)
//
//        // Fill the rectangle (if fill color is set)
//        context.fill(rect)
//
//        // Stroke the rectangle (if stroke color is set)
//        context.stroke(rect)

        guard value != .none else { return }
        if value == .ring {
            drawRing(
                ring: .loop,
                contact: contact,
                state: state,
                rect: CGRect(
                    x: rect.minX + rect.width * 0.10,
                    y: rect.minY + rect.height * 0.10,
                    width: rect.width * 0.80,
                    height: rect.height * 0.80
                ),
                strokeWidth: 10.0
            )
            return
        }
        let text: String? = switch value {
        case .glucose: state.glucose
        case .eventualBG: state.eventualBG
        case .delta: state.delta
        case .trend: state.trend
        case .lastLoopDate: state.lastLoopDate.map({ formatter.string(from: $0) })
        case .cob: state.cobText
        case .iob: state.iobText
        default: nil
        }

        let textColor: Color = switch value {
        case .cob: .loopYellow
        default: color
        }

        if let text = text {
            drawText(
                text: text,
                rect: rect,
                fitHeigh: fitHeigh,
                fontName: fontName,
                fontSize: fontSize,
                fontWeight: fontWeight,
                fontTracking: fontTracking,
                color: textColor
            )
        }
    }

    private static func drawText(
        text: String,
        rect: CGRect,
        fitHeigh: Bool,
        fontName: String?,
        fontSize: Int,
        fontWeight: UIFont.Weight,
        fontTracking: FontTracking,
        color: Color
    ) {
        var theFontSize = fontSize

        func makeAttributes(_ size: Int) -> [NSAttributedString.Key: Any] {
            let font = if let fontName {
                UIFont(name: fontName, size: CGFloat(size)) ?? UIFont.systemFont(ofSize: CGFloat(size), weight: fontWeight)
            } else {
                UIFont.systemFont(ofSize: CGFloat(size), weight: fontWeight)
            }
            return [
                .font: font,
                .foregroundColor: UIColor(color),
                .tracking: fontTracking.value * Double(fontSize)
            ]
        }

        var attributes: [NSAttributedString.Key: Any] = makeAttributes(theFontSize)

        var stringSize = text.size(withAttributes: attributes)
        while stringSize.width > rect.width * 0.90 || fitHeigh && (stringSize.height > rect.height * 0.95), theFontSize > 50 {
            theFontSize = theFontSize - 10
            attributes = makeAttributes(theFontSize)
            stringSize = text.size(withAttributes: attributes)
        }

        text.draw(
            in: CGRectMake(
                rect.minX + (rect.width - stringSize.width) / 2,
                rect.minY + (rect.height - stringSize.height) / 2,
                rect.minX + stringSize.width,
                rect.minY + stringSize.height
            ),
            withAttributes: attributes
        )
    }

    private static func drawRing(
        ring: ContactTrickLargeRing,
        contact: ContactTrickEntry,
        state: ContactTrickState,
        rect: CGRect,
        strokeWidth: Double
    ) {
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }
        switch ring {
        case .loop:
            let color = ringColor(contact: contact, state: state)

            let strokeWidth = strokeWidth
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = min(rect.width, rect.height) / 2 - strokeWidth / 2

            context.setLineWidth(strokeWidth)
            context.setStrokeColor(UIColor(color).cgColor)

            context.addArc(center: center, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)

            context.strokePath()
        case .iob:
            if let iob = state.iob, state.maxIOB > 0.1 {
                drawProgressBar(
                    rect: rect,
                    progress: Double(iob) / Double(state.maxIOB),
                    colors: [contact.darkMode ? .blue : .blue, contact.darkMode ? .pink : .red],
                    strokeWidth: strokeWidth
                )
            }
        case .cob:
            if let cob = state.cob, state.maxCOB > 0.01 {
                drawProgressBar(
                    rect: rect,
                    progress: Double(cob) / Double(state.maxCOB),
                    colors: [.loopYellow, .red],
                    strokeWidth: strokeWidth
                )
            }
        case .iobcob:
            if state.maxIOB > 0.01, state.maxCOB > 0.01 {
                drawDoubleProgressBar(
                    rect: rect,
                    progress1: state.iob.map { Double($0) / Double(state.maxIOB) },
                    progress2: state.cob.map { Double($0) / Double(state.maxCOB) },
                    colors1: [contact.darkMode ? .blue : .blue, contact.darkMode ? .pink : .red],
                    colors2: [.loopYellow, .red],
                    strokeWidth: strokeWidth
                )
            }
        default:
            break
        }
    }

    private static func drawProgressBar(
        rect: CGRect,
        progress: Double,
        colors: [Color],
        strokeWidth: Double
    ) {
        let startAngle: CGFloat = -(.pi + .pi / 4.0)
        let endAngle: CGFloat = .pi / 4.0

        drawGradientArc(
            rect: rect,
            progress: progress,
            colors: colors,
            strokeWidth: strokeWidth,
            startAngle: startAngle,
            endAngle: endAngle,
            gradientDirection: .leftToRight
        )
    }

    private static func drawDoubleProgressBar(
        rect: CGRect,
        progress1: Double?,
        progress2: Double?,
        colors1: [Color],
        colors2: [Color],
        strokeWidth: Double
    ) {
        if let progress1 = progress1 {
            let startAngle1: CGFloat = .pi / 2 + .pi / 5
            let endAngle1: CGFloat = 3 * .pi / 2 - .pi / 5
            drawGradientArc(
                rect: rect,
                progress: progress1,
                colors: colors1,
                strokeWidth: strokeWidth,
                startAngle: startAngle1,
                endAngle: endAngle1,
                gradientDirection: .bottomToTop
            )
        }
        if let progress2 = progress2 {
            let startAngle2: CGFloat = .pi / 2 - .pi / 5
            let endAngle2: CGFloat = -.pi / 2 + .pi / 5
            drawGradientArc(
                rect: rect,
                progress: progress2,
                colors: colors2,
                strokeWidth: strokeWidth,
                startAngle: startAngle2,
                endAngle: endAngle2,
                gradientDirection: .bottomToTop
            )
        }
    }

    private static func drawGradientArc(
        rect: CGRect,
        progress: Double,
        colors: [Color],
        strokeWidth: Double,
        startAngle: Double,
        endAngle: Double,
        gradientDirection: GradientDirection
    ) {
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }

        let colors = colors.map { c in UIColor(c).cgColor }
        let locations: [CGFloat] = [0.0, 1.0]
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors as CFArray,
            locations: locations
        ) else {
            return
        }

        context.saveGState()

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - strokeWidth / 2

        // angle - The angle to the starting point of the arc, measured in radians from the positive x-axis.

        context.setLineWidth(strokeWidth)
        context.setLineCap(.round)

        let circumference = 2 * .pi * radius
        let offsetAngle = (strokeWidth / circumference * 1.1) * 2 * .pi

        let (start, middle, end) = if startAngle > endAngle {
            (
                endAngle,
                startAngle - (startAngle - endAngle) * max(min(progress, 1.0), 0.0),
                startAngle
            )
        } else {
            (
                startAngle,
                startAngle + (endAngle - startAngle) * max(min(progress, 1.0), 0.0),
                endAngle
            )
        }

        if start < middle - offsetAngle {
            let arcPath1 = UIBezierPath()
            arcPath1.addArc(
                withCenter: center,
                radius: radius,
                startAngle: start,
                endAngle: middle - offsetAngle,
                clockwise: true
            )
            context.addPath(arcPath1.cgPath)
        }

        if middle + offsetAngle < end {
            let arcPath2 = UIBezierPath()
            arcPath2.addArc(
                withCenter: center,
                radius: radius,
                startAngle: middle + offsetAngle,
                endAngle: end,
                clockwise: true
            )
            context.addPath(arcPath2.cgPath)
        }

        context.replacePathWithStrokedPath()
        context.clip()

        switch gradientDirection {
        case .bottomToTop:
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: rect.midX, y: rect.maxY),
                end: CGPoint(x: rect.midX, y: rect.minY),
                options: []
            )

        case .leftToRight:
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: rect.minX, y: rect.midY),
                end: CGPoint(x: rect.maxX, y: rect.midY),
                options: []
            )
        }
        context.resetClip()

        let circleCenter = CGPoint(
            x: center.x + radius * cos(middle),
            y: center.y + radius * sin(middle)
        )

        context.setLineWidth(strokeWidth * 0.7)
        context.setStrokeColor(UIColor.white.cgColor)
        context.addArc(
            center: circleCenter,
            radius: 0,
            startAngle: 0,
            endAngle: .pi * 2,
            clockwise: true
        )
        context.strokePath()

        context.restoreGState()
    }

    private static func ringColor(
        contact _: ContactTrickEntry,
        state: ContactTrickState
    ) -> Color {
        guard let lastLoopDate = state.lastLoopDate else {
            return .loopGray
        }
        let delta = Date().timeIntervalSince(lastLoopDate) - Config.lag

        if delta <= 5.minutes.timeInterval {
            return .loopGreen
        } else if delta <= 10.minutes.timeInterval {
            return .loopYellow
        } else {
            return .loopRed
        }
    }

    var uiImage: UIImage {
        ContactPicture.getImage(contact: contact, state: state)
    }

    var body: some View {
        Image(uiImage: uiImage)
            .frame(width: 256, height: 256)
    }
}

extension FontWeight {
    func toUI() -> UIFont.Weight {
        switch self {
        case .light:
            UIFont.Weight.light
        case .regular:
            UIFont.Weight.regular
        case .medium:
            UIFont.Weight.medium
        case .semibold:
            UIFont.Weight.semibold
        case .bold:
            UIFont.Weight.bold
        case .black:
            UIFont.Weight.black
        }
    }
}

enum GradientDirection: Int {
    case leftToRight
    case bottomToTop
}

struct ContactPicturePreview: View {
    @Binding var contact: ContactTrickEntry
    @Binding var state: ContactTrickState

    var body: some View {
        ZStack {
            ContactPicture(contact: $contact, state: $state)
            Circle()
                .stroke(lineWidth: 20)
                .foregroundColor(.white)
        }
        .frame(width: 256, height: 256)
        .clipShape(Circle())
        .preferredColorScheme($contact.wrappedValue.darkMode ? .dark : .light)
    }
}

struct ContactPicture_Previews: PreviewProvider {
    struct Preview: View {
        @State var rangeIndicator: Bool = true
        @State var darkMode: Bool = true
        @State var fontSize: Int = 130
        @State var fontWeight: UIFont.Weight = .bold
        @State var fontName: String? = "AmericanTypewriter"

        var body: some View {
            ContactPicturePreview(
                contact: .constant(
                    ContactTrickEntry(
                        primary: .glucose,
                        top: .delta,
                        bottom: .trend,
                        fontSize: 100,
                        fontWeight: .medium
                    )
                ),
                state: .constant(ContactTrickState(
                    glucose: "6.8",
                    trend: "↗︎",
                    delta: "+0.2",
                    cob: 25,
                    cobText: "25"
                ))
            ).previewDisplayName("bg + trend + delta")

            ContactPicturePreview(
                contact: .constant(
                    ContactTrickEntry(
                        ring1: .iob,
                        primary: .glucose,
                        bottom: .trend,
                        fontSize: 100,
                        fontWeight: .medium
                    )
                ),
                state: .constant(ContactTrickState(
                    glucose: "6.8",
                    trend: "↗︎",
                    iob: 6.1,
                    iobText: "6.1",
                    maxIOB: 8.0
                ))
            ).previewDisplayName("bg + trend + iob ring")

            ContactPicturePreview(
                contact: .constant(
                    ContactTrickEntry(
                        primary: .glucose,
                        top: .ring,
                        bottom: .trend,
                        fontSize: 100,
                        fontWeight: .medium
                    )
                ),
                state: .constant(ContactTrickState(
                    glucose: "6.8",
                    trend: "↗︎",
                    lastLoopDate: .now
                ))

            ).previewDisplayName("bg + trend + ring")

            ContactPicturePreview(
                contact: .constant(
                    ContactTrickEntry(
                        ring1: .loop,
                        primary: .glucose,
                        top: .none,
                        bottom: .trend,
                        fontSize: 100,
                        fontWeight: .medium
                    )
                ),
                state: .constant(ContactTrickState(
                    glucose: "8.8",
                    trend: "→",
                    lastLoopDate: .now
                ))
            ).previewDisplayName("bg + trend + ring1")

            ContactPicturePreview(
                contact: .constant(
                    ContactTrickEntry(
                        ring1: .loop,
                        primary: .glucose,
                        top: .none,
                        bottom: .eventualBG,
                        fontSize: 100,
                        fontWeight: .medium
                    )
                ),
                state: .constant(ContactTrickState(
                    glucose: "6.8",
                    lastLoopDate: .now - 7.minutes,
                    eventualBG: "6.2"
                ))
            ).previewDisplayName("bg + eventual + ring1")

            ContactPicturePreview(
                contact: .constant(
                    ContactTrickEntry(
                        ring1: .loop,
                        primary: .lastLoopDate,
                        top: .none,
                        bottom: .none,
                        fontSize: 100,
                        fontWeight: .medium
                    )
                ),
                state: .constant(ContactTrickState(
                    glucose: "6.8",
                    trend: "↗︎",
                    lastLoopDate: .now - 2.minutes
                ))
            ).previewDisplayName("lastLoopDate + ring1")

            ContactPicturePreview(
                contact: .constant(
                    ContactTrickEntry(
                        ring1: .loop,
                        primary: .glucose,
                        top: .none,
                        bottom: .none,
                        fontSize: 100,
                        fontWeight: .medium
                    )
                ),
                state: .constant(ContactTrickState(
                    glucose: "6.8",
                    lastLoopDate: .now,
                    iob: 6.1,
                    iobText: "6.1",
                    maxIOB: 8.0
                ))
            ).previewDisplayName("bg + ring1 + ring2")

            ContactPicturePreview(
                contact: .constant(
                    ContactTrickEntry(
                        layout: .split,
                        top: .iob,
                        bottom: .cob,
                        fontSize: 100,
                        fontWeight: .medium
                    )
                ),
                state: .constant(ContactTrickState(
                    iob: 1.5,
                    iobText: "1.5",
                    cob: 25,
                    cobText: "25"
                ))
            ).previewDisplayName("iob + cob")

            ContactPicturePreview(
                contact: .constant(
                    ContactTrickEntry(
                        layout: .single,
                        ring1: .iobcob,
                        primary: .none,
                        ringWidth: 8,
                        ringGap: 3,
                        fontSize: 100,
                        fontWeight: .medium
                    )
                ),
                state: .constant(ContactTrickState(
                    iob: 1,
                    iobText: "5.5",
                    cob: 25,
                    cobText: "25",
                    maxIOB: 10,
                    maxCOB: 120
                ))
            ).previewDisplayName("iobcob ring")

            ContactPicturePreview(
                contact: .constant(
                    ContactTrickEntry(
                        layout: .single,
                        ring1: .iobcob,
                        primary: .none,
                        fontSize: 100,
                        fontWeight: .medium
                    )
                ),
                state: .constant(ContactTrickState(
                    iob: -0.2,
                    iobText: "0.0",
                    cob: 0,
                    cobText: "0",
                    maxIOB: 10,
                    maxCOB: 120
                ))
            ).previewDisplayName("iobcob ring (0/0)")

            ContactPicturePreview(
                contact: .constant(
                    ContactTrickEntry(
                        layout: .single,
                        ring1: .iobcob,
                        primary: .none,
                        fontSize: 100,
                        fontWeight: .medium
                    )
                ),
                state: .constant(ContactTrickState(
                    iob: 10,
                    iobText: "0.0",
                    cob: 120,
                    cobText: "0",
                    maxIOB: 10,
                    maxCOB: 120
                ))
            ).previewDisplayName("iobcob ring (max/max)")

            ContactPicturePreview(
                contact: .constant(
                    ContactTrickEntry(
                        layout: .single,
                        ring1: .iobcob,
                        primary: .glucose,
                        bottom: .trend,
                        fontSize: 100,
                        fontWeight: .medium
                    )
                ),
                state: .constant(ContactTrickState(
                    glucose: "6.8",
                    trend: "↗︎",
                    iob: 5.5,
                    iobText: "5.5",
                    cob: 25,
                    cobText: "25",
                    maxIOB: 10,
                    maxCOB: 120
                ))
            ).previewDisplayName("bg + trend + iobcob ring")
        }
    }

    static var previews: some View {
        Preview()
    }
}
