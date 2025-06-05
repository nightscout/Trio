//
//  AlgorithmSettingsContentsStepView.swift
//  Trio
//
//  Created by Cengiz Deniz on 14.04.25
//
import SwiftUI

struct AlgorithmSettingsContentsStepView: View {
    @Bindable var state: Onboarding.StateModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Configure the algorithm…")
                .padding(.horizontal)
                .font(.title3)
                .bold()

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.bgDarkBlue, Color.orange)
                        .symbolRenderingMode(.palette)
                    Text("Important").foregroundStyle(Color.orange)
                }.bold()

                Text("Our strong recommendation is to ")
                    + Text("leave everything on default").bold()
                    + Text(" as a beginner.")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.chart.opacity(0.65))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.orange, lineWidth: 2)
            )
            .cornerRadius(10)

            VStack(alignment: .leading, spacing: 20) {
                Text(
                    "Trio can automatically adapt insulin delivery based on inputs and glucose forecasts. Your algorithm settings play a major part in accurate and effective dosing."
                ).multilineTextAlignment(.leading)

                VStack(alignment: .leading, spacing: 10) {
                    Text("In the next few steps, you’ll configure your algorithm settings for")
                        .font(.headline)
                        .padding(.bottom, 4)
                        .multilineTextAlignment(.leading)

                    BulletPoint(String(localized: "Autosens"))
                    BulletPoint(String(localized: "Super Micro Bolus (SMB)"))
                    BulletPoint(String(localized: "Target Behavior"))
                }

                Text("Only adjust these settings if you’re an advanced or returning user who knows what they’re doing.")
                    .multilineTextAlignment(.leading)
            }
            .padding()
            .background(Color.chart.opacity(0.65))
            .cornerRadius(10)
        }
    }
}
