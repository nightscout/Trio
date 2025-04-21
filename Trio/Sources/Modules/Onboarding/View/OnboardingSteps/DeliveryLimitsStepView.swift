import SwiftUI

struct DeliveryLimitsStepView: View {
    @Bindable var state: Onboarding.StateModel
    let substep: DeliveryLimitSubstep

    @State private var shouldDisplayPicker: Bool = false

    private let settingsProvider = PickerSettingsProvider.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(substep.title)
                .padding(.horizontal)
                .font(.title3)
                .bold()
            Text(substep.hint)
                .font(.subheadline)
                .multilineTextAlignment(.leading)
                .padding(.horizontal)
                .foregroundStyle(Color.secondary)

            switch substep {
            case .maxIOB:
                deliveryLimitInputSection(
                    label: substep.title,
                    displayPicker: $shouldDisplayPicker,
                    setting: settingsProvider.settings.maxIOB,
                    decimalValue: $state.maxIOB
                )
            case .maxBolus:
                deliveryLimitInputSection(
                    label: substep.title,
                    displayPicker: $shouldDisplayPicker,
                    setting: settingsProvider.settings.maxBolus,
                    decimalValue: $state.maxBolus
                )
            case .maxBasal:
                deliveryLimitInputSection(
                    label: substep.title,
                    displayPicker: $shouldDisplayPicker,
                    setting: settingsProvider.settings.maxBasal,
                    decimalValue: $state.maxBasal
                )
            case .maxCOB:
                deliveryLimitInputSection(
                    label: substep.title,
                    displayPicker: $shouldDisplayPicker,
                    setting: settingsProvider.settings.maxCOB,
                    decimalValue: $state.maxCOB
                )
            case .minimumSafetyThreshold:
                deliveryLimitInputSection(
                    label: substep.title,
                    displayPicker: $shouldDisplayPicker,
                    setting: settingsProvider.settings.threshold_setting,
                    decimalValue: $state.minimumSafetyThreshold
                )
            }

            AnyView(substep.description(units: state.units))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .multilineTextAlignment(.leading)
        }
        .onDisappear {
            shouldDisplayPicker = false
        }
    }

    @ViewBuilder private func deliveryLimitInputSection(
        label: String,
        displayPicker: Binding<Bool>,
        setting: PickerSetting,
        decimalValue: Binding<Decimal>
    ) -> some View {
        VStack {
            HStack {
                Text(label)
                Spacer()
                displayText(for: substep, decimalValue: decimalValue.wrappedValue)
                    .foregroundColor(!displayPicker.wrappedValue ? .primary : .accentColor)
                    .onTapGesture {
                        displayPicker.wrappedValue.toggle()
                    }
            }

            if displayPicker.wrappedValue {
                Picker(selection: decimalValue, label: Text(label)) {
                    ForEach(settingsProvider.generatePickerValues(from: setting, units: state.units), id: \.self) { value in
                        displayText(for: substep, decimalValue: value).tag(value)
                    }
                }
                .pickerStyle(WheelPickerStyle())
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(Color.chart.opacity(0.65))
        .cornerRadius(10)
    }

    private func displayText(for substep: DeliveryLimitSubstep, decimalValue: Decimal) -> Text {
        switch substep {
        case .maxBasal:
            return Text("\(decimalValue) \(String(localized: "U/hr", comment: "Insulin unit per hour abbreviation"))")
        case .maxBolus,
             .maxIOB:
            return Text("\(decimalValue) \(String(localized: "U", comment: "Insulin unit abbreviation"))")
        case .maxCOB:
            return Text("\(decimalValue) \(String(localized: "g", comment: "Gram abbreviation"))")
        case .minimumSafetyThreshold:
            let optionallyParsedValue = state.units == .mgdL ? decimalValue : decimalValue.asMmolL
            return Text("\(optionallyParsedValue) \(state.units.rawValue)")
        }
    }
}
