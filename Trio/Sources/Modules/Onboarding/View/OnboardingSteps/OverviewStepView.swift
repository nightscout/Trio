//
//  OverviewStepView.swift
//  Trio
//
//  Created by Cengiz Deniz on 06.04.25.
//
import SwiftUI

struct OverviewStepView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Here is an overview of what to expect:")
                .font(.headline)
                .padding(.horizontal)

            VStack(alignment: .center, spacing: 12) {
                ForEach(
                    nonInfoOnboardingSteps,
                    id: \.self
                ) { step in
                    SettingItemView(step: step, icon: step.iconName, title: step.title, type: .overview)
                }
            }
            .padding()
            .background(Color.chart.opacity(0.65))
            .cornerRadius(10)
        }
    }
}
