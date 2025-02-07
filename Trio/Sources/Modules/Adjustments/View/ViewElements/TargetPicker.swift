import SwiftUI

struct TargetPicker: View {
    let label: String
    @Binding var selection: Decimal
    let options: [Decimal]
    let units: GlucoseUnits
    var hasChanges: Binding<Bool>?
    @Binding var targetStep: Decimal
    @Binding var displayPickerTarget: Bool
    var toggleScrollWheel: (_ picker: Bool) -> Bool

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(
                (units == .mgdL ? selection.description : selection.formattedAsMmolL) + " " + units.rawValue
            )
            .foregroundColor(!displayPickerTarget ? .primary : .accentColor)
            .onTapGesture {
                displayPickerTarget = toggleScrollWheel(displayPickerTarget)
            }
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
                            selection = Adjustments.StateModel.roundTargetToStep(selection, step)
                        }
                        .padding(.top, 10)
                    }
                }
                .frame(maxWidth: .infinity)

                Spacer()

                // Picker on the right side
                Picker(selection: Binding(
                    get: { Adjustments.StateModel.roundTargetToStep(selection, targetStep) },
                    set: {
                        selection = $0
                        hasChanges?.wrappedValue = true // This safely updates if hasChanges is provided
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
