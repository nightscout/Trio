import CoreData
import SwiftUI

struct CurrentGlucoseView: View {
    let timerDate: Date
    let units: GlucoseUnits
    let alarm: GlucoseAlarm?
    let lowGlucose: Decimal
    let highGlucose: Decimal
    let cgmAvailable: Bool
    var currentGlucoseTarget: Decimal
    let glucoseColorScheme: GlucoseColorScheme
    let glucose: [GlucoseStored] // This contains the last two glucose values, no matter if its manual or a cgm reading
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

    var body: some View {
        let triangleColor = Color(red: 0.262745098, green: 0.7333333333, blue: 0.9137254902)

        if cgmAvailable {
            ZStack {
                TrendShape(gradient: angularGradient, color: triangleColor)
                    .rotationEffect(.degrees(rotationDegrees))

                VStack(alignment: .center) {
                    HStack {
                        if let glucoseValue = glucose.last?.glucose {
                            let displayGlucose = units == .mgdL ? Decimal(glucoseValue).description : Decimal(glucoseValue)
                                .formattedAsMmolL

                            var glucoseDisplayColor = Color.primary

                            // TODO: workaround for now: set low value to 55, to have dynamic color shades between 55 and user-set low (approx. 70); same for high glucose
                            let hardCodedLow = Decimal(55)
                            let hardCodedHigh = Decimal(220)
                            let isDynamicColorScheme = glucoseColorScheme == .dynamicColor

                            if Decimal(glucoseValue) <= lowGlucose || Decimal(glucoseValue) >= highGlucose {
                                glucoseDisplayColor = Trio.getDynamicGlucoseColor(
                                    glucoseValue: Decimal(glucoseValue),
                                    highGlucoseColorValue: isDynamicColorScheme ? hardCodedHigh : highGlucose,
                                    lowGlucoseColorValue: isDynamicColorScheme ? hardCodedLow : lowGlucose,
                                    targetGlucose: currentGlucoseTarget,
                                    glucoseColorScheme: glucoseColorScheme
                                )
                            }

                            return Text(
                                glucoseValue == 400 ? "HIGH" : displayGlucose
                            )
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(glucoseDisplayColor)
                        } else {
                            return Text("--")
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        let minutesAgo = -1 * (glucose.last?.date?.timeIntervalSinceNow ?? 0) / 60
                        var minutesAgoString: String {
                            if minutesAgo > 1 {
                                let minuteString = Formatter.timaAgoFormatter.string(for: Double(minutesAgo)) ?? ""
                                return minuteString + "\u{00A0}" + String(localized: "m", comment: "Abbreviation for Minutes")
                            } else {
                                return "<" + "\u{00A0}" + "1" + "\u{00A0}" +
                                    String(localized: "m", comment: "Abbreviation for Minutes")
                            }
                        }

                        Group {
                            Text(minutesAgoString)
                            Text(delta)
                        }
                        .font(.callout).fontWeight(.bold)
                        .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.9) : Color.secondary)
                    }
                    .frame(alignment: .top)
                }
            }
            .onChange(of: glucose.last?.directionEnum) {
                withAnimation {
                    switch glucose.last?.directionEnum {
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
        } else {
            VStack(alignment: .center, spacing: 12) {
                HStack
                    {
                        // no cgm defined so display a generic CGM
                        Image(systemName: "sensor.tag.radiowaves.forward.fill").font(.body).imageScale(.large)
                    }
                HStack {
                    Text("Add CGM").font(.caption).bold()
                }
            }.frame(alignment: .top)
        }
    }

    private var delta: String {
        guard glucose.count >= 2 else {
            return "--"
        }

        let lastGlucose = glucose.last?.glucose ?? 0
        let secondLastGlucose = glucose.first?.glucose ?? 0
        let delta = lastGlucose - secondLastGlucose
        let deltaAsDecimal = units == .mmolL ? Decimal(delta).asMmolL : Decimal(delta)
        return deltaFormatter.string(from: deltaAsDecimal as NSNumber) ?? "--"
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
