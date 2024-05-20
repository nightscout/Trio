import SwiftUI

struct PumpView: View {
    @Binding var reservoir: Decimal?
    @Binding var battery: Battery?
    @Binding var name: String
    @Binding var expiresAtDate: Date?
    @Binding var timerDate: Date
    @Binding var pumpStatusHighlightMessage: String?

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

    var body: some View {
        if let pumpStatusHighlightMessage = pumpStatusHighlightMessage { // display message instead pump info
            VStack(alignment: .center) {
                Text(pumpStatusHighlightMessage).font(.footnote).fontWeight(.bold)
                    .multilineTextAlignment(.center).frame(maxWidth: /*@START_MENU_TOKEN@*/ .infinity/*@END_MENU_TOKEN@*/)
            }.frame(width: 100)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if reservoir == nil && battery == nil {
                    VStack(alignment: .center, spacing: 12) {
                        HStack { // no cgm defined so display a generic CGM
                            Image(systemName: "keyboard.onehanded.left").font(.body).imageScale(.large)
                        }
                        HStack {
                            Text("Add pump").font(.caption).bold()
                        }
                    }.frame(alignment: .top)
                }

                if let reservoir = reservoir {
                    HStack {
                        Image(systemName: "drop.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 10)
                            .foregroundColor(reservoirColor)
                        if reservoir == 0xDEAD_BEEF {
                            Text("50+ " + NSLocalizedString("U", comment: "Insulin unit")).font(.footnote)
                                .fontWeight(.bold)
                        } else {
                            Text(
                                reservoirFormatter
                                    .string(from: reservoir as NSNumber)! +
                                    NSLocalizedString(" U", comment: "Insulin unit")
                            )
                            .font(.footnote).fontWeight(.bold)
                        }
                    }.frame(alignment: .top)
                }
                if let battery = battery, battery.display ?? false, expiresAtDate == nil {
                    HStack {
                        Image(systemName: "battery.100")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 10)
                            .foregroundColor(batteryColor)
                        Text("\(Int(battery.percent ?? 100)) %").font(.footnote)
                            .fontWeight(.bold)
                    }.frame(alignment: .bottom)
                }

                if let date = expiresAtDate {
                    HStack {
                        Image(systemName: "stopwatch.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 10)
                            .foregroundColor(timerColor)
                        Text(remainingTimeString(time: date.timeIntervalSince(timerDate))).font(.footnote)
                            .fontWeight(.bold)
                    }.frame(alignment: .bottom)
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
        guard let battery = battery, let percent = battery.percent else {
            return .gray
        }

        switch percent {
        case ...10:
            return .loopRed
        case ...20:
            return .loopYellow
        default:
            return .loopGreen
        }
    }

    private var reservoirColor: Color {
        guard let reservoir = reservoir else {
            return .gray
        }

        switch reservoir {
        case ...10:
            return .loopRed
        case ...30:
            return .loopYellow
        default:
            return .insulin
        }
    }

    private var timerColor: Color {
        guard let expisesAt = expiresAtDate else {
            return .gray
        }

        let time = expisesAt.timeIntervalSince(timerDate)

        switch time {
        case ...8.hours.timeInterval:
            return .loopRed
        case ...1.days.timeInterval:
            return .loopYellow
        default:
            return .loopGreen
        }
    }
}

#Preview("message") {
    PumpView(
        reservoir: .constant(Decimal(10.0)),
        battery: .constant(nil),
        name: .constant("Pump test"),
        expiresAtDate: .constant(Date().addingTimeInterval(24.hours)),
        timerDate: .constant(Date()),
        pumpStatusHighlightMessage: .constant("⚠️\n Insulin suspended")
    )
}

#Preview("pump reservoir") {
    PumpView(
        reservoir: .constant(Decimal(40.0)),
        battery: .constant(Battery(percent: 50, voltage: 2.0, string: BatteryState.normal, display: true)),
        name: .constant("Pump test"),
        expiresAtDate: .constant(nil),
        timerDate: .constant(Date().addingTimeInterval(-24.hours)),
        pumpStatusHighlightMessage: .constant(nil)
    )
}

#Preview("pump expiration") {
    PumpView(
        reservoir: .constant(Decimal(10.0)),
        battery: .constant(Battery(percent: 50, voltage: 2.0, string: BatteryState.normal, display: false)),
        name: .constant("Pump test"),
        expiresAtDate: .constant(Date().addingTimeInterval(2.hours)),
        timerDate: .constant(Date().addingTimeInterval(2.hours)),
        pumpStatusHighlightMessage: .constant(nil)
    )
}

#Preview("no pump") {
    PumpView(
        reservoir: .constant(nil),
        battery: .constant(nil),
        name: .constant(""),
        expiresAtDate: .constant(nil),
        timerDate: .constant(Date()),
        pumpStatusHighlightMessage: .constant(nil)
    )
}
