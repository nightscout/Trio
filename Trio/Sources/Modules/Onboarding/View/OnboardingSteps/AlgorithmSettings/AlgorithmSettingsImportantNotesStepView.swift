//
//  AlgorithmSettingsImportantNotesStepView.swift
//  Trio
//
//  Created by Cengiz Deniz on 14.04.25
//
import SwiftUI

struct AlgorithmSettingsImportantNotesStepView: View {
    @Bindable var state: Onboarding.StateModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("A few important notes…")
                .padding(.horizontal)
                .font(.title3)
                .bold()

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.bgDarkBlue, Color.orange)
                        .symbolRenderingMode(.palette)
                    Text("Important").foregroundStyle(Color.orange)
                }.bold()

                Text("Dynamic ISF requires at least ") + Text("7 days")
                    .bold() + Text(" of usage data and is not yet configurable.")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.chart.opacity(0.65))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.orange, lineWidth: 2)
            )
            .cornerRadius(10)

            VStack(alignment: .leading, spacing: 10) {
                Text("Some helpful reminders:")
                    .font(.headline)
                    .padding(.bottom, 4)
                    .multilineTextAlignment(.leading)

                BulletPoint(
                    String(
                        localized: "Even if you’re an updating user, you’ll be guided through the algorithm settings configuration step-by-step."
                    )
                )
                BulletPoint(String(localized: "All additional \"advanced settings\" have been reset."))
                BulletPoint(
                    String(localized: "The duration of insulin action (DIA) is now locked to Trio’s new default of 10 hours.")
                )
                BulletPoint(
                    String(localized: "We strongly recommend not changing DIA — it’s essential to stable and safe operation.")
                )
            }
            .padding()
            .background(Color.chart.opacity(0.65))
            .cornerRadius(10)
        }
    }
}
