import Foundation
import SwiftUI

// MARK: - Bolus Input View

struct BolusInputView: View {
    @Environment(\.dismiss) var dismiss
    @State private var bolusAmount = 0.0
    @State private var isExternalInsulin = false
    let state: WatchState

    var body: some View {
        NavigationView {
            VStack {
                Picker("Bolus", selection: $bolusAmount) {
                    ForEach(0 ... 100, id: \.self) { number in
                        Text(String(format: "%.1f U", Double(number) / 10))
                            .tag(Double(number) / 10)
                    }
                }

                Toggle("External Insulin", isOn: $isExternalInsulin)
                    .toggleStyle(.switch)
                    .padding(.horizontal)

                Button(isExternalInsulin ? "Add External Insulin" : "Add Bolus") {
                    state.sendBolusRequest(Decimal(bolusAmount), isExternal: isExternalInsulin)
                    dismiss()
                }
                .buttonStyle(.bordered)
                .tint(.blue)
            }
            .navigationTitle("Add Insulin")
        }
    }
}
