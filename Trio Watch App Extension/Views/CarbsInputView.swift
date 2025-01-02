import Foundation
import SwiftUI

// MARK: - Carbs Input View

struct CarbsInputView: View {
    @Environment(\.dismiss) var dismiss
    @State private var carbsAmount = 0
    let state: WatchState

    var body: some View {
        NavigationView {
            VStack {
                Picker("Carbs", selection: $carbsAmount) {
                    ForEach(0 ... 100, id: \.self) { amount in
                        Text("\(amount)g").tag(amount)
                    }
                }

                Button("Add Carbs") {
                    state.sendCarbsRequest(carbsAmount)
                    dismiss()
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }
            .navigationTitle("Add Carbs")
        }
    }
}
