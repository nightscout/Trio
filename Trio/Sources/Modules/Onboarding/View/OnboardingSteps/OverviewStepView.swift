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
                ForEach(Array(OnboardingChapter.allCases.enumerated()), id: \.element.id) { index, chapter in
                    overviewItem(
                        stepIndex: index + 1,
                        title: chapter.title,
                        duration: chapter.duration,
                        description: chapter.overviewDescription
                    )

                    if index < (OnboardingChapter.allCases.count - 1) {
                        Divider()
                    }
                }
            }
            .padding()
            .background(Color.chart.opacity(0.65))
            .cornerRadius(10)
        }
    }

    @ViewBuilder private func overviewItem(
        stepIndex: Int,
        title: String,
        duration: String,
        description: String
    ) -> some View {
        VStack(alignment: .leading) {
            HStack {
                HStack(spacing: 14) {
                    stepCount(stepIndex)
                    Text(title).font(.headline)
                }

                Spacer()

                Text("\(duration) \(String(localized: "min"))")
                    .font(.subheadline)
            }

            Text(description)
                .font(.footnote)
                .foregroundStyle(Color.secondary)
                .padding(.vertical, 8)
                .multilineTextAlignment(.leading)
        }
    }

    @ViewBuilder private func stepCount(_ count: Int) -> some View {
        Text(count.description)
            .font(.subheadline.bold())
            .frame(width: 26, height: 26, alignment: .center)
            .background(Color.blue)
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }
}
