import SwiftUI

struct PumpView: View {
    @Binding var reservoir: Decimal?
    @Binding var battery: Battery?
    @Binding var name: String
    @Binding var expiresAtDate: Date?
    @Binding var timerDate: Date

    @State var state: Home.StateModel

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

    var body: some View {
        HStack {
            Text("IOB").font(.callout).foregroundColor(.secondary)
            Text(
                (numberFormatter.string(from: (state.suggestion?.iob ?? 0) as NSNumber) ?? "0") +
                    NSLocalizedString(" U", comment: "Insulin unit")
            )
            .font(.callout).fontWeight(.bold)

            Spacer()

            Text("COB").font(.callout).foregroundColor(.secondary)
            Text(
                (numberFormatter.string(from: (state.suggestion?.cob ?? 0) as NSNumber) ?? "0") +
                    NSLocalizedString(" g", comment: "gram of carbs")
            )
            .font(.callout).fontWeight(.bold)

            Spacer()

            if let reservoir = reservoir {
                HStack {
                    Image(systemName: "drop.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 15)
                        .foregroundColor(reservoirColor)
                    if reservoir == 0xDEAD_BEEF {
                        Text("50+ " + NSLocalizedString("U", comment: "Insulin unit")).font(.callout)
                            .fontWeight(.bold)
                    } else {
                        Text(
                            reservoirFormatter
                                .string(from: reservoir as NSNumber)! + NSLocalizedString(" U", comment: "Insulin unit")
                        )
                        .font(.callout).fontWeight(.bold)
                    }
                }
            }

            Spacer()

            if let battery = battery, battery.display ?? false, expiresAtDate == nil {
                HStack {
                    Image(systemName: "battery.100")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 15)
                        .foregroundColor(batteryColor)
                    Text("\(Int(battery.percent ?? 100)) %").font(.callout)
                        .fontWeight(.bold)
                }
            }

            if let date = expiresAtDate {
                HStack {
                    Image(systemName: "stopwatch.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 15)
                        .foregroundColor(timerColor)

                    Text(remainingTimeString(time: date.timeIntervalSince(timerDate))).font(.callout)
                        .fontWeight(.bold)
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
