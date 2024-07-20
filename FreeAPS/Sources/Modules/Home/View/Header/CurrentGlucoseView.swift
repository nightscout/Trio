import CoreData
import SwiftUI

struct CurrentGlucoseView: View {
    @Binding var timerDate: Date
    @Binding var units: GlucoseUnits
    @Binding var alarm: GlucoseAlarm?
    @Binding var lowGlucose: Decimal
    @Binding var highGlucose: Decimal
    var glucose: [GlucoseStored]
    var manualGlucose: [GlucoseStored]

    @State private var rotationDegrees: Double = 0.0
    @State private var angularGradient = AngularGradient(colors: [
        Color(red: 0.7215686275, green: 0.3411764706, blue: 1),
        Color(red: 0.6235294118, green: 0.4235294118, blue: 0.9803921569),
        Color(red: 0.4862745098, green: 0.5450980392, blue: 0.9529411765),
        Color(red: 0.3411764706, green: 0.6666666667, blue: 0.9254901961),
        Color(red: 0.262745098, green: 0.7333333333, blue: 0.9137254902),
        Color(red: 0.7215686275, green: 0.3411764706, blue: 1)
    ], center: .center, startAngle: .degrees(270), endAngle: .degrees(-90))

    @Environment(\.colorScheme) var colorScheme

    private var combinedGlucoseValues: [GlucoseStored] {
        // Combine and sort the glucose values
        let combined = (glucose + manualGlucose).sorted { $0.date ?? Date() > $1.date ?? Date() }
        return combined
    }

    private var glucoseFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal

        if units == .mmolL {
            formatter.maximumFractionDigits = 1
            formatter.minimumFractionDigits = 1
            formatter.roundingMode = .halfUp
        } else {
            formatter.maximumFractionDigits = 0
        }
        return formatter
    }

    private var deltaFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        if units == .mmolL {
            formatter.maximumFractionDigits = 1
            formatter.minimumFractionDigits = 1
            formatter.roundingMode = .halfUp
        } else {
            formatter.maximumFractionDigits = 0
        }
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
        let triangleColor = Color(red: 0.262745098, green: 0.7333333333, blue: 0.9137254902)

        ZStack {
            TrendShape(gradient: angularGradient, color: triangleColor)
                .rotationEffect(.degrees(rotationDegrees))

            VStack(alignment: .center) {
                HStack {
                    if let glucoseValue = combinedGlucoseValues.first?.glucose {
                        let displayGlucose = convertGlucose(glucoseValue, to: units)
                        Text(
                            glucoseValue == 400 ? "HIGH" :
                                glucoseFormatter.string(from: NSNumber(value: displayGlucose)) ?? "--"
                        )
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(alarm == nil ? colourGlucoseText : .loopRed)
                    } else {
                        Text("--")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
                HStack {
                    let minutesAgo = -1 * (combinedGlucoseValues.first?.date?.timeIntervalSinceNow ?? 0) / 60
                    let text = timaAgoFormatter.string(for: Double(minutesAgo)) ?? ""
                    Text(
                        minutesAgo <= 1 ? "< 1 " + NSLocalizedString("min", comment: "Short form for minutes") : (
                            text + " " +
                                NSLocalizedString("min", comment: "Short form for minutes") + " "
                        )
                    )
                    .font(.caption2).foregroundColor(colorScheme == .dark ? Color.white.opacity(0.9) : Color.secondary)

                    Text(
                        delta
                    )
                    .font(.caption2).foregroundColor(colorScheme == .dark ? Color.white.opacity(0.9) : Color.secondary)
                }.frame(alignment: .top)
            }
        }
        .onChange(of: combinedGlucoseValues.first?.directionEnum) { newDirection in
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
                case nil,
                     .notComputable,
                     .rateOutOfRange:
                    rotationDegrees = 0
                default:
                    rotationDegrees = 0
                }
            }
        }
    }

    private func convertGlucose(_ value: Int16, to units: GlucoseUnits) -> Double {
        switch units {
        case .mmolL:
            return Double(value) / 18.0
        case .mgdL:
            return Double(value)
        }
    }

    private var delta: String {
        guard combinedGlucoseValues.count >= 2 else {
            return "--"
        }

        let lastGlucose = combinedGlucoseValues.first?.glucose ?? 0
        let secondLastGlucose = combinedGlucoseValues.dropFirst().first?.glucose ?? 0
        let delta = lastGlucose - secondLastGlucose
        let deltaAsDecimal = units == .mmolL ? Decimal(delta).asMmolL : Decimal(delta)
        return deltaFormatter.string(from: deltaAsDecimal as NSNumber) ?? "--"
    }

    var colourGlucoseText: Color {
        // Fetch the first glucose reading and convert it to Int for comparison
        let whichGlucose = Int(combinedGlucoseValues.first?.glucose ?? 0)

        // Define default color based on the color scheme
        let defaultColor: Color = colorScheme == .dark ? .white : .black

        // Ensure the thresholds are logical
        guard lowGlucose < highGlucose else { return .primary }

        // Perform range checks using Int converted values
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

        path.move(to: CGPoint(x: rect.midX, y: rect.minY + 15))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))

        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.midY + 10))

        path.closeSubpath()

        return path
    }
}

struct TrendShape: View {
    @Environment(\.colorScheme) var colorScheme

    let gradient: AngularGradient
    let color: Color

    var body: some View {
        HStack(alignment: .center) {
            ZStack {
                Group {
                    CircleShape(gradient: gradient)
                    TriangleShape(color: color)
                }.shadow(color: Color.black.opacity(colorScheme == .dark ? 0.75 : 0.33), radius: colorScheme == .dark ? 5 : 3)
                CircleShape(gradient: gradient)
            }
        }
    }
}

struct CircleShape: View {
    @Environment(\.colorScheme) var colorScheme

    let gradient: AngularGradient

    var body: some View {
        Circle()
            .stroke(gradient, lineWidth: 6)
            .background(Circle().fill(Color.chart))
            .frame(width: 130, height: 130)
    }
}

struct TriangleShape: View {
    let color: Color

    var body: some View {
        Triangle()
            .fill(color)
            .frame(width: 35, height: 35)
            .rotationEffect(.degrees(90))
            .offset(x: 85)
    }
}
