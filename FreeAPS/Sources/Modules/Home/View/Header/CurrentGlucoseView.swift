import CoreData
import SwiftUI

struct CurrentGlucoseView: View {
    @Binding var timerDate: Date
    @Binding var units: GlucoseUnits
    @Binding var alarm: GlucoseAlarm?
    @Binding var lowGlucose: Decimal
    @Binding var highGlucose: Decimal
//    var glucoseFromPersistence: [GlucoseStored]

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

    @FetchRequest(
        entity: GlucoseStored.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \GlucoseStored.date, ascending: false)],
        predicate: NSPredicate.predicateFor30MinAgo,
        animation: Animation.bouncy
    ) var glucoseFromPersistence: FetchedResults<GlucoseStored>

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
        let triangleColor = Color(red: 0.262745098, green: 0.7333333333, blue: 0.9137254902)

        ZStack {
            TrendShape(gradient: angularGradient, color: triangleColor)
                .rotationEffect(.degrees(rotationDegrees))

            VStack(alignment: .center) {
                HStack {
                    let glucoseValue = glucoseFromPersistence.first?.glucose ?? 100
                    let displayGlucose = convertGlucose(glucoseValue, to: units)

                    Text(
                        glucoseValue == 400 ? "HIGH" :
                            glucoseFormatter.string(from: NSNumber(value: displayGlucose)) ?? "--"
                    )
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(alarm == nil ? colourGlucoseText : .loopRed)
                }
                HStack {
                    let minutesAgo = -1 * (glucoseFromPersistence.first?.date?.timeIntervalSinceNow ?? 0) / 60
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
        .onChange(of: glucoseFromPersistence.first?.direction) { newDirection in
            withAnimation {
                switch newDirection {
                case "DoubleUp",
                     "SingleUp",
                     "TripleUp":
                    rotationDegrees = -90
                case "FortyFiveUp":
                    rotationDegrees = -45
                case "Flat":
                    rotationDegrees = 0
                case "FortyFiveDown":
                    rotationDegrees = 45
                case "DoubleDown",
                     "SingleDown",
                     "TripleDown":
                    rotationDegrees = 90
                case "NONE",
                     "NOT COMPUTABLE",
                     "RATE OUT OF RANGE":
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
        guard glucoseFromPersistence.count >= 2 else {
            return "--"
        }

        let lastGlucose = glucoseFromPersistence.first?.glucose ?? 0
        let secondLastGlucose = glucoseFromPersistence.dropFirst().first?.glucose ?? 0
        let delta = lastGlucose - secondLastGlucose
        let deltaAsDecimal = Decimal(delta)
        return deltaFormatter.string(from: deltaAsDecimal as NSNumber) ?? "--"
    }

    var colourGlucoseText: Color {
        // Fetch the first glucose reading and convert it to Int for comparison
        let whichGlucose = Int(glucoseFromPersistence.first?.glucose ?? 0)

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
