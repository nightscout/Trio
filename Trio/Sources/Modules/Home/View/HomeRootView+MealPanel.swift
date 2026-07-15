import Foundation
import SwiftUI

// MARK: - Zone C: meal panel (IOB / COB / delivery rate)

extension Home.RootView {
    var basalString: String? {
        var rate: NSNumber = 0
        var manualBasalString = ""

        guard let apsManager = state.apsManager else {
            return nil
        }

        if apsManager.isScheduledBasal == true {
            guard let scheduledRate = scheduledBasalDeliveryRate(at: Date()) else {
                return nil
            }
            rate = scheduledRate
        } else {
            guard let lastTempBasal = state.tempBasals.last?.tempBasal, let tempRate = lastTempBasal.rate else {
                return nil
            }
            if apsManager.isManualTempBasal {
                manualBasalString = String(
                    localized: " - Manual Basal ⚠️",
                    comment: "Manual Temp basal"
                )
            }
            rate = tempRate
        }

        let rateString = Formatter.decimalFormatterWithThreeFractionDigits.string(from: rate) ?? "0"
        return rateString + String(localized: " U/hr", comment: "Unit per hour with space") +
            manualBasalString
    }

    func scheduledBasalDeliveryRate(at when: Date) -> NSNumber? {
        let calendar = Calendar(identifier: .gregorian)
        // calendar.timeZone = timeZone /// should come from pumpManager in case it's different!

        let hours = calendar.component(.hour, from: when)
        let minutes = calendar.component(.minute, from: when)
        let totalMinutes = hours * 60 + minutes

        if let rate = findBasalRateForOffset(for: totalMinutes, in: state.basalProfile) {
            return NSDecimalNumber(decimal: rate)
        }
        return nil
    }

    @ViewBuilder func mealPanel() -> some View {
        HStack {
            HStack {
                Image(systemName: "syringe.fill")
                    .font(.callout)
                    .foregroundColor(Color.insulin)
                Text(
                    (
                        Formatter.decimalFormatterWithTwoFractionDigits
                            .string(from: state.currentIOB as NSNumber) ?? "0"
                    ) +
                        String(localized: " U", comment: "Insulin unit")
                )
                .font(.callout).fontWeight(.bold).fontDesign(.rounded)
            }

            Spacer()

            HStack {
                Image(systemName: "fork.knife")
                    .font(.callout)
                    .foregroundColor(.loopYellow)
                Text(
                    (
                        Formatter.decimalFormatterWithTwoFractionDigits.string(
                            from: NSNumber(value: state.enactedAndNonEnactedDeterminations.first?.cob ?? 0)
                        ) ?? "0"
                    ) +
                        String(localized: " g", comment: "gram of carbs")
                )
                .font(.callout).fontWeight(.bold).fontDesign(.rounded)
            }

            Spacer()

            if state.maxIOB == 0.0 {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text("MaxIOB: 0 U")
                }.bold()
                    .foregroundStyle(Color.red)
                    .font(.callout)
            } else {
                HStack {
                    /// Only display the insulin delivery rate info if the pump is not
                    /// suspended and is available (e.g., pod is paired & not faulted).
                    let pumpAvailable = state.apsManager.isScheduledBasal != nil
                    if !state.apsManager.isSuspended && pumpAvailable {
                        Image(systemName: "drop.circle")
                            .font(.callout)
                            .foregroundColor(.insulinTintColor)
                        if let basalString = self.basalString {
                            /// Adjust opacity when displaying a scheduled basal rate
                            let opacity = state.apsManager?.isScheduledBasal == true ? 0.6 : 1.0
                            if basalString.count > 5 {
                                Text(basalString)
                                    .font(.callout).fontWeight(.bold).fontDesign(.rounded)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                    .truncationMode(.tail)
                                    .allowsTightening(true)
                                    .opacity(opacity)
                            } else {
                                // Short strings can just display normally
                                Text(basalString)
                                    .font(.callout).fontWeight(.bold).fontDesign(.rounded)
                                    .opacity(opacity)
                            }
                        } else {
                            Text("No Data")
                                .font(.callout).fontWeight(.bold).fontDesign(.rounded)
                        }
                    }
                }
            }
        }.padding(.horizontal)
    }
}
