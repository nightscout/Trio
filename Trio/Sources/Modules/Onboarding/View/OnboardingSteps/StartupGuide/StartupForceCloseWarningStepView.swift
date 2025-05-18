//
//  StartupForceCloseWarningStepView.swift
//  Trio
//
//  Created by Cengiz Deniz on 27.04.25.
//
import SwiftUI

struct StartupForceCloseWarningStepView: View {
    @Bindable var state: Onboarding.StateModel

    @Environment(\.openURL) var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("One last thing, before you begin...")
                .font(.title3)
                .bold()

            VStack(alignment: .leading, spacing: 10) {
                BulletPoint(
                    String(localized: "You can pause at any time. If you feel like taking a break, do it and put the phone down!")
                )
                BulletPoint(
                    String(
                        localized: "All entries you made during Onboarding will be saved automatically when you complete the wizard."
                    )
                )
            }
            .padding()
            .background(Color.chart.opacity(0.65))
            .cornerRadius(10)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.bgDarkBlue, Color.orange)
                        .symbolRenderingMode(.palette)
                    Text("Important").foregroundStyle(Color.orange)
                }.bold()

                Text("Just be aware: if you force quit the app before finishing onboarding, your progress will not be saved.")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.chart.opacity(0.65))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.orange, lineWidth: 2)
            )
            .cornerRadius(10)
        }
    }
}
