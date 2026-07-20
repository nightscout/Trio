import SwiftUI

struct AlarmBGSection: View {
    let header: String
    let footer: String?
    let title: String
    let range: ClosedRange<Decimal>
    let step: Decimal
    let units: GlucoseUnits
    @Binding var valueMgDL: Decimal

    @State private var showPicker = false

    var body: some View {
        Section(
            header: Text(header),
            footer: footer.map { Text($0) }
        ) {
            VStack(spacing: 0) {
                HStack {
                    Text(title)
                    Spacer()
                    Text(valueMgDL.formatted(for: units))
                        .foregroundColor(showPicker ? .accentColor : .primary)
                    Text(units.rawValue)
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { showPicker.toggle() }

                if showPicker {
                    Picker(title, selection: $valueMgDL) {
                        ForEach(pickerValues, id: \.self) { value in
                            Text(value.formatted(for: units)).tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                }
            }
        }.listRowBackground(Color.chart)
    }

    private var pickerValues: [Decimal] {
        let setting = PickerSetting(
            value: valueMgDL,
            step: step,
            min: range.lowerBound,
            max: range.upperBound,
            type: .glucose
        )
        return PickerSettingsProvider.shared.generatePickerValues(from: setting, units: units)
    }
}
