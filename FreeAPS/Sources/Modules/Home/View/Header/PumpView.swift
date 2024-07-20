import CoreData
import SwiftUI

struct PumpView: View {
    @Binding var reservoir: Decimal?
    @Binding var name: String
    @Binding var expiresAtDate: Date?
    @Binding var timerDate: Date
    @Binding var timeZone: TimeZone?
    @Binding var pumpStatusHighlightMessage: String?
    var battery: [OpenAPS_Battery]

    @Environment(\.colorScheme) var colorScheme

    private var reservoirFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }

    private var batteryFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        return formatter
    }

    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter
    }

    private var dateFormatter: DateFormatter {
        let dateFormatter = DateFormatter()
        dateFormatter.timeStyle = .short
        return dateFormatter
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
                            .font(.system(size: 16))
                            .foregroundColor(reservoirColor)
                        if reservoir == 0xDEAD_BEEF {
                            Text("50+ " + NSLocalizedString("U", comment: "Insulin unit"))
                                .font(.system(size: 15, design: .rounded))
                        } else {
                            Text(
                                reservoirFormatter
                                    .string(from: reservoir as NSNumber)! + NSLocalizedString(" U", comment: "Insulin unit")
                            )
                            .font(.system(size: 16, design: .rounded))
                        }
                    }

                    if let timeZone = timeZone, timeZone.secondsFromGMT() != TimeZone.current.secondsFromGMT() {
                        Image(systemName: "clock.badge.exclamationmark.fill")
                            .font(.system(size: 16))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.red, Color(.warning))
                    }
                }

                if (battery.first?.display) != nil, expiresAtDate == nil {
                    HStack {
                        Image(systemName: "battery.100")
                            .font(.system(size: 16))
                            .foregroundColor(batteryColor)
                        Text("\(Int(battery.first?.percent ?? 100)) %").font(.system(size: 16, design: .rounded))
                    }
                }

                if let date = expiresAtDate {
                    HStack {
                        Image(systemName: "stopwatch.fill")
                            .font(.system(size: 16))
                            .foregroundColor(timerColor)

                        Text(remainingTimeString(time: date.timeIntervalSince(timerDate)))
                            .font(.system(size: 16, design: .rounded))
                    }
                }
            }
        }
    }

    private func remainingTimeString(time: TimeInterval) -> String {
        guard time > 0 else {
            return NSLocalizedString("Replace pod", comment: "View/Header when pod expired")
        }

        var time = time
        let days = Int(time / 1.days.timeInterval)
        time -= days.days.timeInterval
        let hours = Int(time / 1.hours.timeInterval)
        time -= hours.hours.timeInterval
        let minutes = Int(time / 1.minutes.timeInterval)

        if days >= 1 {
            return "\(days)" + NSLocalizedString("d", comment: "abbreviation for days") + " \(hours)" +
                NSLocalizedString("h", comment: "abbreviation for hours")
        }

        if hours >= 1 {
            return "\(hours)" + NSLocalizedString("h", comment: "abbreviation for hours")
        }

        return "\(minutes)" + NSLocalizedString("m", comment: "abbreviation for minutes")
    }

    private var batteryColor: Color {
        guard let battery = battery.first else {
            return .gray
        }

        switch battery.percent {
        case ...10:
            return .red
        case ...20:
            return .yellow
        default:
            return .green
        }
    }

    private var reservoirColor: Color {
        guard let reservoir = reservoir else {
            return .gray
        }

        switch reservoir {
        case ...10:
            return .red
        case ...30:
            return .yellow
        default:
            return .blue
        }
    }

    private var timerColor: Color {
        guard let expisesAt = expiresAtDate else {
            return .gray
        }

        let time = expisesAt.timeIntervalSince(timerDate)

        switch time {
        case ...8.hours.timeInterval:
            return .red
        case ...1.days.timeInterval:
            return .yellow
        default:
            return .green
        }
    }
}

//#Preview("message") {
//    PumpView(
//        reservoir: .constant(Decimal(10.0)),
//        battery: .constant(nil),
//        name: .constant("Pump test"),
//        expiresAtDate: .constant(Date().addingTimeInterval(24.hours)),
//        timerDate: .constant(Date()),
//        pumpStatusHighlightMessage: .constant("⚠️\n Insulin suspended")
//    )
//}
//
//#Preview("pump reservoir") {
//    PumpView(
//        reservoir: .constant(Decimal(40.0)),
//        battery: .constant(Battery(percent: 50, voltage: 2.0, string: BatteryState.normal, display: true)),
//        name: .constant("Pump test"),
//        expiresAtDate: .constant(nil),
//        timerDate: .constant(Date().addingTimeInterval(-24.hours)),
//        pumpStatusHighlightMessage: .constant(nil)
//    )
//}
//
//#Preview("pump expiration") {
//    PumpView(
//        reservoir: .constant(Decimal(10.0)),
//        battery: .constant(Battery(percent: 50, voltage: 2.0, string: BatteryState.normal, display: false)),
//        name: .constant("Pump test"),
//        expiresAtDate: .constant(Date().addingTimeInterval(2.hours)),
//        timerDate: .constant(Date().addingTimeInterval(2.hours)),
//        pumpStatusHighlightMessage: .constant(nil)
//    )
//}
//
//#Preview("no pump") {
//    PumpView(
//        reservoir: .constant(nil),
//        name: .constant(nil),
//        expiresAtDate: .constant(""),
//        timerDate: .constant(nil),
//        timeZone: .constant(Date()),
//        pumpStatusHighlightMessage: .constant(nil)
//    )
//}
