import SwiftUI

extension History.RootView {
    var manualGlucoseFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        if state.units == .mgdL {
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

    @ViewBuilder func addGlucoseView() -> some View {
        let limitLow: Decimal = state.units == .mgdL ? Decimal(14) : 14.asMmolL
        let limitHigh: Decimal = state.units == .mgdL ? Decimal(720) : 720.asMmolL

        NavigationView {
            VStack {
                Form {
                    Section {
                        HStack {
                            Text("New Glucose")
                            TextFieldWithToolBar(
                                text: $state.manualGlucose,
                                placeholder: " ... ",
                                keyboardType: state.units == .mgdL ? .numberPad : .decimalPad,
                                numberFormatter: manualGlucoseFormatter,
                                initialFocus: true,
                                unitsText: state.units.rawValue
                            )
                        }
                    }.listRowBackground(Color.chart)

                    Section {
                        HStack {
                            Button {
                                state.addManualGlucose()
                                isAmountUnconfirmed = false
                                showManualGlucose = false
                                state.mode = .glucose
                            }
                            label: { Text("Save") }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .disabled(state.manualGlucose < limitLow || state.manualGlucose > limitHigh)
                        }
                    }
                    .listRowBackground(
                        state.manualGlucose < limitLow || state
                            .manualGlucose > limitHigh ? Color(.systemGray4) : Color(.systemBlue)
                    )
                    .tint(.white)
                }.scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            }
            .onAppear(perform: configureView)
            .navigationTitle("Add Glucose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        showManualGlucose = false
                    }
                }
            }
        }
    }
}
