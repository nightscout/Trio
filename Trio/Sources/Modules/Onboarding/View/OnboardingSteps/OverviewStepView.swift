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
                overviewItem(
                    stepIndex: 1,
                    title: String(localized: "Prepare Trio"),
                    duration: "3-5",
                    description: String(
                        localized: "Configure diagnostics sharing, optionally sync with Nightscout, and enter essentials."
                    )
                )

                Divider()

                overviewItem(
                    stepIndex: 2,
                    title: String(localized: "Therapy Settings"),
                    duration: "5-10",
                    description: String(
                        localized: "Define your glucose targets, basal rates, carb ratios, and insulin sensitivities."
                    )
                )

                Divider()

                overviewItem(
                    stepIndex: 3,
                    title: String(localized: "Delivery Limits"),
                    duration: "3-5",
                    description: String(
                        localized: "Set boundaries for insulin delivery and carb entries to help Trio keep you safe."
                    )
                )

                Divider()

                overviewItem(
                    stepIndex: 4,
                    title: String(localized: "Algorithm Settings"),
                    duration: "5-10",
                    description: String(
                        localized: "Customize Trio’s algorithm features. Most users start with the recommended settings."
                    )
                )

                Divider()

                overviewItem(
                    stepIndex: 5,
                    title: String(localized: "Permission Requests"),
                    duration: "1",
                    description: String(
                        localized: "Authorize Trio to send notifications and use Bluetooth. You must allow both for Trio to work properly."
                    )
                )
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
