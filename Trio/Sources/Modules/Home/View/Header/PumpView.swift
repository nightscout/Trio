import CoreData
import SwiftUI

struct PumpView: View {
    let reservoir: Decimal?
    let name: String
    let expiresAtDate: Date?
    let timerDate: Date
    let pumpStatusHighlightMessage: String?
    let battery: [OpenAPS_Battery]
    @Environment(\.colorScheme) var colorScheme

    private var batteryFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        return formatter
    }

    var body: some View {
        if let pumpStatusHighlightMessage = pumpStatusHighlightMessage { // display message instead pump info
            VStack(alignment: .center) {
                Text(pumpStatusHighlightMessage).font(.footnote).fontWeight(.bold)
                    .multilineTextAlignment(.center).frame(maxWidth: /*@START_MENU_TOKEN@*/ .infinity/*@END_MENU_TOKEN@*/)
            }.frame(width: 100)
        } else {
            VStack(alignment: .leading, spacing: 20) {
                if reservoir == nil && battery.isEmpty {
                    VStack(alignment: .center, spacing: 12) {
                        HStack {
                            Image(systemName: "keyboard.onehanded.left")
                                .font(.body)
                                .imageScale(.large)
                        }
                        HStack {
                            Text("Add pump")
                                .font(.caption)
                                .bold()
                        }
                    }
                    .frame(alignment: .top)
                }
                if let reservoir = reservoir {
                    HStack {
                        Image(systemName: "cross.vial.fill")
                            .font(.callout)

                        if reservoir == 0xDEAD_BEEF {
                            Text("50+ " + String(localized: "U", comment: "Insulin unit"))
                                .font(.callout)
                                .fontWeight(.bold)
                                .fontDesign(.rounded)
                        } else {
                            Text(
                                Formatter.integerFormatter
                                    .string(from: reservoir as NSNumber)! + String(localized: " U", comment: "Insulin unit")
                            )
                            .font(.callout)
                            .fontWeight(.bold)
                            .fontDesign(.rounded)
                        }
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .foregroundStyle(reservoirColor)
                    .overlay(
                        Capsule()
                            .stroke(reservoirColor.opacity(0.4), lineWidth: 2)
                    )
                }

                if (battery.first?.display) != nil, let shouldBatteryDisplay = battery.first?.display, shouldBatteryDisplay {
                    HStack {
                        Image(systemName: "battery.100")
                            .font(.callout)
                            .foregroundStyle(batteryColor)
                        Text("\(Formatter.integerFormatter.string(for: battery.first?.percent ?? 100) ?? "100") %")
                            .font(.callout).fontWeight(.bold).fontDesign(.rounded)
                    }
                }

                if let date = expiresAtDate {
                    HStack {
                        Image(systemName: "stopwatch.fill")
                            .font(.callout)
                            .foregroundStyle(timerColor)

                        let remainingTimeString = remainingTimeString(time: date.timeIntervalSince(timerDate))

                        Text(remainingTimeString)
                            .font(date.timeIntervalSince(timerDate) > 0 ? .callout : .subheadline)
                            .fontWeight(.bold)
                            .fontDesign(.rounded)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(
                                // If the string is > 6 chars, i.e., exceeds "xd yh", limit width to 80 pts
                                // This forces the "Replace pod" string to wrap to 2 lines.
                                maxWidth: remainingTimeString.count > 6 ? 80 : .infinity,
                                alignment: .leading
                            )
                    }
                    // aligns the stopwatch icon exactly with the first pixel of the reservoir icon
                    .padding(.leading, date.timeIntervalSince(timerDate) > 0 ? 12 : 0)
                }
            }
        }
    }

    private func remainingTimeString(time: TimeInterval) -> String {
        guard time > 0 else {
            return String(localized: "Replace pod", comment: "View/Header when pod expired")
        }

        var time = time
        let days = Int(time / 1.days.timeInterval)
        time -= days.days.timeInterval
        let hours = Int(time / 1.hours.timeInterval)
        time -= hours.hours.timeInterval
        let minutes = Int(time / 1.minutes.timeInterval)

        if days >= 1 {
            return "\(days)" + String(localized: "d", comment: "abbreviation for days") + " \(hours)" +
                String(localized: "h", comment: "abbreviation for hours")
        }

        if hours >= 1 {
            return "\(hours)" + String(localized: "h", comment: "abbreviation for hours")
        }

        return "\(minutes)" + String(localized: "m", comment: "abbreviation for minutes")
    }

    private var batteryColor: Color {
        guard let battery = battery.first else {
            return .gray
        }

        switch battery.percent {
        case ...10:
            return Color.loopRed
        case ...20:
            return Color.orange
        default:
            return Color.loopGreen
        }
    }

    private var reservoirColor: Color {
        guard let reservoir = reservoir else {
            return .gray
        }

        switch reservoir {
        case ...10:
            return Color.loopRed
        case ...30:
            return Color.orange
        default:
            return Color.insulin
        }
    }

    private var timerColor: Color {
        guard let expisesAt = expiresAtDate else {
            return .gray
        }

        let time = expisesAt.timeIntervalSince(timerDate)

        switch time {
        case ...8.hours.timeInterval:
            return Color.loopRed
        case ...1.days.timeInterval:
            return Color.orange
        default:
            return Color.loopGreen
        }
    }
}

// #Preview("message") {
//    PumpView(
//        reservoir: .constant(Decimal(10.0)),
//        battery: .constant(nil),
//        name: .constant("Pump test"),
//        expiresAtDate: .constant(Date().addingTimeInterval(24.hours)),
//        timerDate: .constant(Date()),
//        pumpStatusHighlightMessage: .constant("⚠️\n Insulin suspended")
//    )
// }
//
// #Preview("pump reservoir") {
//    PumpView(
//        reservoir: .constant(Decimal(40.0)),
//        battery: .constant(Battery(percent: 50, voltage: 2.0, string: BatteryState.normal, display: true)),
//        name: .constant("Pump test"),
//        expiresAtDate: .constant(nil),
//        timerDate: .constant(Date().addingTimeInterval(-24.hours)),
//        pumpStatusHighlightMessage: .constant(nil)
//    )
// }
//
// #Preview("pump expiration") {
//    PumpView(
//        reservoir: .constant(Decimal(10.0)),
//        battery: .constant(Battery(percent: 50, voltage: 2.0, string: BatteryState.normal, display: false)),
//        name: .constant("Pump test"),
//        expiresAtDate: .constant(Date().addingTimeInterval(2.hours)),
//        timerDate: .constant(Date().addingTimeInterval(2.hours)),
//        pumpStatusHighlightMessage: .constant(nil)
//    )
// }
//
// #Preview("no pump") {
//    PumpView(
//        reservoir: .constant(nil),
//        name: .constant(nil),
//        expiresAtDate: .constant(""),
//        timerDate: .constant(nil),
//        timeZone: .constant(Date()),
//        pumpStatusHighlightMessage: .constant(nil)
//    )
// }
