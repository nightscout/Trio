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
    @State private var angularGradient: AngularGradient = defaultGradient()

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
        let triangleColor = Color(red: 0.729, green: 0.337, blue: 1)

        ZStack {
            TrendShape(gradient: angularGradient, color: triangleColor)
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
                    setupAngularGradient(startAngle: 135, endAngle: -45)

                case .fortyFiveUp:
                    rotationDegrees = -45
                    setupAngularGradient(startAngle: 180, endAngle: 0)

                case .flat:
                    rotationDegrees = 0
                    setupAngularGradient(startAngle: 225, endAngle: 45)

                case .fortyFiveDown:
                    rotationDegrees = 45
                    setupAngularGradient(startAngle: 270, endAngle: 90)

                case .doubleDown,
                     .singleDown,
                     .tripleDown:
                    rotationDegrees = 90
                    setupAngularGradient(startAngle: -45, endAngle: 135)

                case .none,
                     .notComputable,
                     .rateOutOfRange:
                    rotationDegrees = 0
                    setupAngularGradient(startAngle: 225, endAngle: 45)

                @unknown default:
                    rotationDegrees = 0
                    setupAngularGradient(startAngle: 225, endAngle: 45)
                }
            }
        }
    }

    private func setupAngularGradient(startAngle: Double, endAngle: Double) {
        angularGradient = AngularGradient(colors: [
            Color(red: 0.729, green: 0.337, blue: 1),
            Color(red: 0.263, green: 0.733, blue: 0.914),
            Color(red: 0.263, green: 0.733, blue: 0.914),
            Color(red: 0.263, green: 0.733, blue: 0.914),
            Color(red: 0.263, green: 0.733, blue: 0.914),
            Color(red: 0.729, green: 0.337, blue: 1)
        ], center: .center, startAngle: .degrees(startAngle), endAngle: .degrees(endAngle))
    }

    private static func defaultGradient(startAngle: Double = 180, endAngle: Double = 0) -> AngularGradient {
        AngularGradient(colors: [
            Color(red: 0.729, green: 0.337, blue: 1),
            Color(red: 0.263, green: 0.733, blue: 0.914),
            Color(red: 0.263, green: 0.733, blue: 0.914),
            Color(red: 0.263, green: 0.733, blue: 0.914),
            Color(red: 0.263, green: 0.733, blue: 0.914),
            Color(red: 0.729, green: 0.337, blue: 1)
        ], center: .center, startAngle: .degrees(startAngle), endAngle: .degrees(endAngle))
    }

    var colourGlucoseText: Color {
        let whichGlucose = recentGlucose?.glucose ?? 0
        let defaultColor: Color = colorScheme == .dark ? .white : .black

        guard lowGlucose < highGlucose else { return .primary }

        switch whichGlucose {
        case 0 ..< Int(lowGlucose):
            return .loopRed
        case Int(lowGlucose) ..< Int(highGlucose):
            return defaultColor
        case Int(highGlucose)...:
            return .loopYellow
        default:
            return defaultColor
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
    let gradient: AngularGradient
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

    let gradient: AngularGradient

    var body: some View {
        let colorBackground: Color = colorScheme == .dark ? .black.opacity(0.8) : .white

        Circle()
            .stroke(gradient, lineWidth: 10)
            .shadow(
                color: colorScheme == .dark ? Color(red: 0.02745098039, green: 0.1098039216, blue: 0.1411764706) :
                    Color.black.opacity(0.33),
                radius: 3
            )
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
