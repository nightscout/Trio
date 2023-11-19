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
    @State var gradientColor = LinearGradient(
        gradient: Gradient(colors: [
            Color(red: 0.298, green: 0.071, blue: 0.4),
            Color(red: 0.435, green: 0.114, blue: 0.573),
            Color(red: 0.741, green: 0.204, blue: 0.914),
            Color(red: 0.831, green: 0.263, blue: 1)
        ]),
        startPoint: .leading,
        endPoint: .trailing
    )

    @Environment(\.colorScheme) var colorScheme

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
        let colourGlucoseText: Color = colorScheme == .dark ? .white : .black
        let triangleColor = Color(red: 0.831, green: 0.263, blue: 1)

        ZStack {
            TrendShape(gradient: gradientColor, color: triangleColor)
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
                    .foregroundColor(alarm == nil ? colourGlucoseText : .loopRed)
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
                    gradientColor = LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.298, green: 0.071, blue: 0.4),
                            Color(red: 0.435, green: 0.114, blue: 0.573),
                            Color(red: 0.741, green: 0.204, blue: 0.914),
                            Color(red: 0.831, green: 0.263, blue: 1)
                        ]),
                        startPoint: .bottom,
                        endPoint: .top
                    )

                case .fortyFiveUp:
                    rotationDegrees = -45
                    gradientColor = LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.298, green: 0.071, blue: 0.4),
                            Color(red: 0.435, green: 0.114, blue: 0.573),
                            Color(red: 0.741, green: 0.204, blue: 0.914),
                            Color(red: 0.831, green: 0.263, blue: 1)
                        ]),
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    )

                case .flat:
                    rotationDegrees = 0
                    gradientColor = LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.298, green: 0.071, blue: 0.4),
                            Color(red: 0.435, green: 0.114, blue: 0.573),
                            Color(red: 0.741, green: 0.204, blue: 0.914),
                            Color(red: 0.831, green: 0.263, blue: 1)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )

                case .fortyFiveDown:
                    rotationDegrees = 45
                    gradientColor = LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.298, green: 0.071, blue: 0.4),
                            Color(red: 0.435, green: 0.114, blue: 0.573),
                            Color(red: 0.741, green: 0.204, blue: 0.914),
                            Color(red: 0.831, green: 0.263, blue: 1)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                case .doubleDown,
                     .singleDown,
                     .tripleDown:
                    rotationDegrees = 90
                    gradientColor = LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.298, green: 0.071, blue: 0.4),
                            Color(red: 0.435, green: 0.114, blue: 0.573),
                            Color(red: 0.741, green: 0.204, blue: 0.914),
                            Color(red: 0.831, green: 0.263, blue: 1)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )

                case .none,
                     .notComputable,
                     .rateOutOfRange:
                    rotationDegrees = 0
                    gradientColor = LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.298, green: 0.071, blue: 0.4),
                            Color(red: 0.435, green: 0.114, blue: 0.573),
                            Color(red: 0.741, green: 0.204, blue: 0.914),
                            Color(red: 0.831, green: 0.263, blue: 1)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )

                @unknown default:
                    rotationDegrees = 0
                    gradientColor = LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.298, green: 0.071, blue: 0.4),
                            Color(red: 0.435, green: 0.114, blue: 0.573),
                            Color(red: 0.741, green: 0.204, blue: 0.914),
                            Color(red: 0.831, green: 0.263, blue: 1)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
            }
        }
    }

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
    let gradient: LinearGradient
    let color: Color

    var body: some View {
        HStack(alignment: .center) {
            ZStack {
                CircleShape(gradient: gradient)
                TriangleShape(color: color)
            }
        }
    }
}

struct CircleShape: View {
    @Environment(\.colorScheme) var colorScheme

    let gradient: LinearGradient

    var body: some View {
        let colorBackground: Color = colorScheme == .dark ? .black : .white

        Circle()
            .stroke(gradient, lineWidth: 10)
            .shadow(radius: 3)
            .background(Circle().fill(colorBackground))
            .frame(width: 110, height: 110)
    }
}

struct TriangleShape: View {
    let color: Color

    var body: some View {
        Triangle()
            .fill(color)
            .frame(width: 30, height: 30)
            .rotationEffect(.degrees(90))
            .offset(x: 65)
    }
}
