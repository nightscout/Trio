import CoreData
import Foundation
import SwiftUI

struct TargetPicker: View {
    let label: String
    @Binding var selection: Decimal
    let options: [Decimal]
    let units: GlucoseUnits
    @Binding var hasChanges: Bool
    @Binding var targetStep: Decimal
    @Binding var displayPickerTarget: Bool
    var toggleScrollWheel: (_ picker: Bool) -> Bool

    var body: some View {
        VStack {
            HStack {
                Text(label)
                Spacer()
                Text(
                    (units == .mgdL ? selection.description : selection.formattedAsMmolL) + " " + units.rawValue
                )
                .foregroundColor(!displayPickerTarget ? .primary : .accentColor)
            }
            .onTapGesture {
                displayPickerTarget = toggleScrollWheel(displayPickerTarget)
            }
            if displayPickerTarget {
                HStack {
                    // Radio buttons and text on the left side
                    VStack(alignment: .leading) {
                        // Radio buttons for step iteration
                        let stepChoices: [Decimal] = units == .mgdL ? [1, 5] : [1, 9]
                        ForEach(stepChoices, id: \.self) { step in
                            let label = (units == .mgdL ? step.description : step.formattedAsMmolL) + " " +
                                units.rawValue
                            RadioButton(
                                isSelected: targetStep == step,
                                label: label
                            ) {
                                targetStep = step
                                selection = OverrideConfig.StateModel.roundTargetToStep(selection, step)
                            }
                            .padding(.top, 10)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Spacer()

                    // Picker on the right side
                    Picker(selection: Binding(
                        get: { OverrideConfig.StateModel.roundTargetToStep(selection, targetStep) },
                        set: {
                            selection = $0
                            hasChanges = true
                        }
                    ), label: Text("")) {
                        ForEach(options, id: \.self) { option in
                            Text((units == .mgdL ? option.description : option.formattedAsMmolL) + " " + units.rawValue)
                                .tag(option)
                        }
                    }
                    .pickerStyle(WheelPickerStyle())
                    .frame(maxWidth: .infinity)
                }
                .listRowSeparator(.hidden, edges: .top)
            }
        }
    }
}

enum TargetHelper {
    func computeHalfBasalTarget(
        usingTarget initialTarget: Decimal? = nil,
        usingPercentage initialPercentage: Double? = nil
    ) -> Double {
        let adjustmentPercentage = initialPercentage ?? percentage
        let adjustmentRatio = Decimal(adjustmentPercentage / 100)
        let tempTargetValue: Decimal = initialTarget ?? tempTargetTarget
        var halfBasalTargetValue = halfBasalTarget
        if adjustmentRatio != 1 {
            halfBasalTargetValue = ((2 * adjustmentRatio * normalTarget) - normalTarget - (adjustmentRatio * tempTargetValue)) /
                (adjustmentRatio - 1)
        }
        return round(Double(halfBasalTargetValue))
    }

    func computeSliderLow(usingTarget initialTarget: Decimal? = nil) -> Double {
        let calcTarget = initialTarget ?? tempTargetTarget
        guard calcTarget != 0 else { return 15 }

        let shouldRaiseSensitivity = settingsManager.preferences.highTemptargetRaisesSensitivity
        let isExerciseModeActive = settingsManager.preferences.exerciseMode
        let isTargetNormalOrLower = calcTarget <= normalTarget

        let minSens = (isTargetNormalOrLower || (!shouldRaiseSensitivity && !isExerciseModeActive)) ? 100 : 15

        return Double(max(0, minSens))
    }

    func computeSliderHigh(usingTarget initialTarget: Decimal? = nil) -> Double {
        let calcTarget = initialTarget ?? tempTargetTarget
        guard calcTarget != 0 else { return Double(maxValue * 100) }

        let shouldLowerSensitivity = settingsManager.preferences.lowTemptargetLowersSensitivity
        let isTargetNormalOrHigher = calcTarget >= normalTarget

        let maxSens = (isTargetNormalOrHigher || !shouldLowerSensitivity) ? 100 : Double(maxValue * 100)

        return maxSens
    }

    func computeAdjustedPercentage(
        usingHBT initialHalfBasalTarget: Decimal? = nil,
        usingTarget initialTarget: Decimal? = nil
    ) -> Decimal {
        let halfBasalTargetValue = initialHalfBasalTarget ?? halfBasalTarget
        let calcTarget = initialTarget ?? tempTargetTarget
        let deviationFromNormal = halfBasalTargetValue - normalTarget

        let adjustmentFactor = deviationFromNormal + (calcTarget - normalTarget)
        let adjustmentRatio: Decimal = (deviationFromNormal * adjustmentFactor <= 0) ? maxValue : deviationFromNormal /
            adjustmentFactor

        return min(adjustmentRatio, maxValue)
    }
}
