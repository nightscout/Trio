//
//  AlgorithmSettingsStepView.swift
//  Trio
//
//  Created by Cengiz Deniz on 14.04.25
//
import SwiftUI

struct AlgorithmSettingsStepView: View {
    @Bindable var state: Onboarding.StateModel

    @State private var shouldDisplayPicker: Bool = false
    @State private var decimalPlaceholder: Decimal = 0.0
    @State private var booleanPlaceholder: Bool = false

    private let settingsProvider = PickerSettingsProvider.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Configure the algorithm…")
                .padding(.horizontal)
                .font(.title3)
                .bold()

            VStack(alignment: .leading, spacing: 10) {
                Text(
                    "Trio’s algorithm can automatically adapt insulin delivery based on inputs and glucose forecsasts. Your algorithm settings play a major part in accurate and effective dosing."
                )

                Text("Our strong recommendation is to ")
                    + Text("leave everything on default").bold()
                    + Text(" as a beginner.")

                Text("Only adjust these settings if you’re an advanced or returning user who knows what they’re doing.")
            }
            .padding(.horizontal)

            Divider()
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 10) {
                Text("A few important notes:")
                    .font(.headline)
                    .padding(.bottom, 4)

                BulletPoint(String(localized: "Dynamic ISF requires at least 7 days of usage data and is not yet configurable."))
                BulletPoint(String(localized: "Even if you’re an updating user, you’ll be guided through this step-by-step."))
                BulletPoint(String(localized: "All additional \"advanced settings\" have been reset."))
                BulletPoint(
                    String(localized: "The duration of insulin action (DIA) is now locked to Trio’s new default of 10 hours.")
                )
                BulletPoint(
                    String(localized: "We strongly recommend not changing DIA — it’s essential to stable and safe operation.")
                )
            }
            .padding(.horizontal)
        }
    }
}
