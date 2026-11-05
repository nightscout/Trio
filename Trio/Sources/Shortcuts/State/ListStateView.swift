import AppIntents
import Foundation
import SwiftUI

struct ListStateView: View {
    var state: StateResults

    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
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
        VStack(spacing: 0) {
            stateRow
            adjustmentsRow
        }
    }

    /// Same layout as the in-app adjustment panel, so the snippet reads like the app.
    @ViewBuilder private var adjustmentsRow: some View {
        let overrideLabel = state.overrideName.flatMap { name in
            state.overrideDetails.map { AdjustmentLabel.forOverride(name: name, details: $0) }
        }
        let tempTargetLabel = state.tempTargetName.flatMap { name in
            state.tempTargetDetails.map { AdjustmentLabel.forTempTarget(name: name, details: $0) }
        }

        if let overrideLabel, let tempTargetLabel {
            HStack(spacing: 0) {
                HStack {
                    overrideLabel
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)

                HStack {
                    tempTargetLabel
                    Spacer(minLength: 0)
                }
                .padding(.leading, 8)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        } else if let adjustmentLabel = overrideLabel ?? tempTargetLabel {
            HStack {
                adjustmentLabel
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
    }

    private var stateRow: some View {
        HStack(alignment: .center) {
            Spacer()

            HStack {
                Text("IOB").font(.caption).foregroundColor(.secondary)
                Text(
                    (numberFormatter.string(from: (state.iob ?? 0) as NSNumber) ?? "0") +
                        String(localized: " U", comment: "Insulin unit")
                )
                .font(.body).fontWeight(.bold)
            }
            HStack {
                Text("COB").font(.caption).foregroundColor(.secondary)
                Text(
                    (numberFormatter.string(from: (state.cob ?? 0) as NSNumber) ?? "0") +
                        String(localized: " g", comment: "gram of carbs")
                )
                .font(.body).fontWeight(.bold)
            }
            Spacer()
            HStack {
                Text(
                    state.glucose
                )
                .font(.title).fontWeight(.bold).foregroundColor(.loopGreen)
                image
            }
            HStack {
                let minutes = -1 * state.date.timeIntervalSinceNow / 60
                let text = timaAgoFormatter.string(for: Double(minutes)) ?? ""
                Text(
                    minutes <= 1 ? "< 1 " + String(localized: "min", comment: "Short form for minutes") : (
                        text + " " +
                            String(localized: "min", comment: "Short form for minutes") + " "
                    )
                )
                .font(.caption2).foregroundColor(.secondary)

                Text(
                    state.delta
                )
                .font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .padding(.bottom, 6)
        //       .background(Color.gray.opacity(0.2))
    }

    var image: Image {
        let direction = state.trend
        switch direction {
        case "DoubleUp",
             "SingleUp",
             "TripleUp":
            return Image(systemName: "arrow.up")
        case "FortyFiveUp":
            return Image(systemName: "arrow.up.right")
        case "Flat":
            return Image(systemName: "arrow.forward")
        case "FortyFiveDown":
            return Image(systemName: "arrow.down.forward")
        case "DoubleDown",
             "SingleDown",
             "TripleDown":
            return Image(systemName: "arrow.down")

        case "NONE",
             "NOT COMPUTABLE",
             "RATE OUT OF RANGE":
            return Image(systemName: "arrow.left.and.right")
        default:
            return Image(systemName: "arrow.left.and.right")
        }
    }
}
