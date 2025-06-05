//
//  StartupReturningUserStepView.swift
//  Trio
//
//  Created by Cengiz Deniz on 27.04.25.
//
import SwiftUI

struct StartupReturningUserStepView: View {
    @Bindable var state: Onboarding.StateModel
    let wasMigrationSuccessful: Bool

    @Environment(\.openURL) var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Already using Trio and updating from an older version?")
                .padding(.horizontal)
                .font(.title3)
                .bold()

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.bgDarkBlue, Color.orange)
                        .symbolRenderingMode(.palette)
                    Text("Important").foregroundStyle(Color.orange)
                }.bold()

                if !wasMigrationSuccessful {
                    Text("Your last 24 hr of treatment data (pump events, carb entries, glucose trace, etc.) are not migrated.")
                }

                Divider().overlay(Color.orange)

                Text("Your algorithm settings (previously called \"OpenAPS settings\") are reset to defaults.")
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
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill").foregroundStyle(Color.bgDarkBlue, Color.blue)
                        .symbolRenderingMode(.palette)
                    Text("Information").foregroundStyle(Color.blue)
                }.bold()

                Text("While onboarding, Trio continues to operate with your prior settings.")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.chart.opacity(0.65))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.blue, lineWidth: 2)
            )
            .cornerRadius(10)

            VStack(alignment: .leading, spacing: 10) {
                Text("Here's what you can expect to be preserved:")
                    .font(.headline)
                    .padding(.bottom, 4)

                if wasMigrationSuccessful {
                    BulletPoint(
                        String(
                            localized: "Your last 24 hr of treatment data (pump events, carb entries, glucose trace, etc.) are migrated."
                        )
                    )
                }
                BulletPoint(String(localized: "Your pump and CGM configurations are retained and fully functional."))
                BulletPoint(
                    String(
                        localized: "Your therapy settings (basal rates, carb ratios, insulin sensitivities and glucose targets) are carried over."
                    )
                )
                BulletPoint(String(localized: "We recommend reviewing them carefully — Trio will guide you step-by-step."))
                BulletPoint(
                    String(
                        localized: "You will also be guided through re-configuring your algorithm settings, respecting Trio's new guardrails."
                    )
                )
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.chart.opacity(0.65))
            .cornerRadius(10)
        }
    }
}
