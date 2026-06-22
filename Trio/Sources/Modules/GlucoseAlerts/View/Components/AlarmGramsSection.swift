import SwiftUI

/// Mirror of `AlarmBGSection` but for gram-valued thresholds (carbsRequired).
/// Single fixed unit, no mg/dL ↔︎ mmol/L conversion.
struct AlarmGramsSection: View {
    let header: String
    let footer: String?
    let title: String
    let range: ClosedRange<Int>
    let step: Int
    @Binding var valueGrams: Decimal

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
                    Text("\(Int(NSDecimalNumber(decimal: valueGrams).intValue))")
                        .foregroundColor(showPicker ? .accentColor : .primary)
                    Text(String(localized: "g", comment: "Abbreviation for grams"))
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { showPicker.toggle() }

                if showPicker {
                    Picker(title, selection: Binding(
                        get: { Int(NSDecimalNumber(decimal: valueGrams).intValue) },
                        set: { valueGrams = Decimal($0) }
                    )) {
                        ForEach(Array(stride(from: range.lowerBound, through: range.upperBound, by: step)), id: \.self) { v in
                            Text("\(v)").tag(v)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                }
            }
        }.listRowBackground(Color.chart)
    }
}
