import SwiftUI

struct CurrentGlucoseView: View {
    @Binding var recentGlucose: BloodGlucose?
    @Binding var timerDate: Date
    @Binding var delta: Int?
    @Binding var units: GlucoseUnits
    @Binding var alarm: GlucoseAlarm?
    @Binding var lowGlucose: Decimal
    @Binding var highGlucose: Decimal

    @State private var rotationDegrees: Double = 0.0

    private var glucoseFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        if units == .mmolL {
            formatter.minimumFractionDigits = 1
            formatter.maximumFractionDigits = 1
        }
        formatter.roundingMode = .halfUp
        return formatter
    }

    private var deltaFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.positivePrefix = "  +"
        formatter.negativePrefix = "  -"
        return formatter
    }

    private var timaAgoFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.negativePrefix = ""
        return formatter
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        ZStack {
            TrendShape(color: colorOfGlucose)
                .rotationEffect(.degrees(rotationDegrees))

            VStack(alignment: .center) {
                HStack {
                    Text(
                        (recentGlucose?.glucose ?? 100) == 400 ? "HIGH" : recentGlucose?.glucose
                            .map {
                                glucoseFormatter
                                    .string(from: Double(units == .mmolL ? $0.asMmolL : Decimal($0)) as NSNumber)! }
                            ?? "--"
                    )
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(alarm == nil ? colorOfGlucose : .loopRed)

                    //                image
                }
                HStack {
                    let minutesAgo = -1 * (recentGlucose?.dateString.timeIntervalSinceNow ?? 0) / 60
                    let text = timaAgoFormatter.string(for: Double(minutesAgo)) ?? ""
                    Text(
                        minutesAgo <= 1 ? "< 1 " + NSLocalizedString("min", comment: "Short form for minutes") : (
                            text + " " +
                                NSLocalizedString("min", comment: "Short form for minutes") + " "
                        )
                    )
                    .font(.caption2).foregroundColor(.secondary)

                    Text(
                        delta
                            .map {
                                deltaFormatter.string(from: Double(units == .mmolL ? $0.asMmolL : Decimal($0)) as NSNumber)!
                            } ?? "--"
                    )
                    .font(.caption2).foregroundColor(.secondary)
                }.frame(alignment: .top)
            }
        }
        .onChange(of: recentGlucose?.direction) { newDirection in
            withAnimation {
                switch newDirection {
                case .doubleUp,
                     .singleUp,
                     .tripleUp:
                    rotationDegrees = -90
                case .fortyFiveUp:
                    rotationDegrees = -45
                case .flat:
                    rotationDegrees = 0
                case .fortyFiveDown:
                    rotationDegrees = 45
                case .doubleDown,
                     .singleDown,
                     .tripleDown:
                    rotationDegrees = 90
                case .none,
                     .notComputable,
                     .rateOutOfRange:
                    rotationDegrees = 0
                @unknown default:
                    rotationDegrees = 0
                }
            }
        }
    }

//    var image: Image {
//        guard let direction = recentGlucose?.direction else {
//            return Image(systemName: "arrow.left.and.right")
//        }
//
//        switch direction {
//        case .doubleUp,
//             .singleUp,
//             .tripleUp:
//            return Image(systemName: "arrow.up")
//        case .fortyFiveUp:
//            return Image(systemName: "arrow.up.right")
//        case .flat:
//            return Image(systemName: "arrow.forward")
//        case .fortyFiveDown:
//            return Image(systemName: "arrow.down.forward")
//        case .doubleDown,
//             .singleDown,
//             .tripleDown:
//            return Image(systemName: "arrow.down")
//
//        case .none,
//             .notComputable,
//             .rateOutOfRange:
//            return Image(systemName: "arrow.left.and.right")
//        }
//    }

    var colorOfGlucose: Color {
        let whichGlucose = recentGlucose?.glucose ?? 0

        guard lowGlucose < highGlucose else { return .primary }

        switch whichGlucose {
        case 0 ..< Int(lowGlucose):
            return .loopRed
        case Int(lowGlucose) ..< Int(highGlucose):
            return .loopGreen
        case Int(highGlucose)...:
            return .loopYellow
        default:
            return .loopYellow
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let cornerRadius: CGFloat = 8

        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - cornerRadius), control: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()

        return path
    }
}

struct TrendShape: View {
    let color: Color

    var body: some View {
        HStack(alignment: .center, spacing: -5) {
            CircleShape(color: color)
            TriangleShape(color: color)
        }
    }
}

struct CircleShape: View {
    @Environment(\.colorScheme) var colorScheme

    let color: Color

    var body: some View {
        let colorBackground: Color = colorScheme == .dark ? .gray.opacity(0.1) : .white

        Circle()
            .stroke(color, lineWidth: 10)
            .background(Circle().fill(colorBackground))
            .frame(width: 110, height: 110)
            .offset(x: 13)
    }
}

struct TriangleShape: View {
    let color: Color

    var body: some View {
        Triangle()
            .fill(color)
            .frame(width: 30, height: 30)
            .rotationEffect(.degrees(90))
            .offset(x: 13)
    }
}
