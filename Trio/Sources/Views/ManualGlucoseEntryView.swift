import SwiftUI

/// Manual (finger-stick) glucose entry sheet; mirrors History's add-glucose
/// form so both entry points look identical.
struct ManualGlucoseEntryView: View {
    let units: GlucoseUnits
    @Binding var isPresented: Bool
    let onSave: (Decimal) -> Void

    @State private var amount: Decimal = 0

    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    private var formatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        if units == .mgdL {
            formatter.maximumIntegerDigits = 3
            formatter.maximumFractionDigits = 0
        } else {
            formatter.maximumIntegerDigits = 2
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 1
        }
        formatter.roundingMode = .halfUp
        return formatter
    }

    var body: some View {
        let limitLow: Decimal = units == .mgdL ? Decimal(14) : 14.asMmolL
        let limitHigh: Decimal = units == .mgdL ? Decimal(720) : 720.asMmolL

        NavigationView {
            VStack {
                Form {
                    Section {
                        HStack {
                            Text("New Glucose")
                            TextFieldWithToolBar(
                                text: $amount,
                                placeholder: " ... ",
                                keyboardType: units == .mgdL ? .numberPad : .decimalPad,
                                numberFormatter: formatter,
                                initialFocus: true,
                                unitsText: units.rawValue
                            )
                        }
                    }.listRowBackground(Color.chart)

                    Section {
                        HStack {
                            Button {
                                onSave(amount)
                                isPresented = false
                            }
                            label: { Text("Save") }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .disabled(amount < limitLow || amount > limitHigh)
                        }
                    }
                    .listRowBackground(
                        amount < limitLow || amount > limitHigh ? Color(.systemGray4) : Color(.systemBlue)
                    )
                    .tint(.white)
                }.scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            }
            .navigationTitle("Add Glucose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        isPresented = false
                    }
                }
            }
        }
    }
}
