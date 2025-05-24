//
// Trio
// StartupGuideStepView.swift
// Created by Deniz Cengiz on 2025-04-27.
// Last edited by Deniz Cengiz on 2025-04-27.
// Most contributions by Deniz Cengiz.
//
// Documentation available under: https://triodocs.org/

import SwiftUI

struct StartupGuideStepView: View {
    @Bindable var state: Onboarding.StateModel

    @Environment(\.openURL) var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Before you begin…")
                .padding(.horizontal)
                .font(.title3)
                .bold()

            VStack {
                VStack(alignment: .leading, spacing: 10) {
                    BulletPoint(String(localized: "Take a deep breath — you've got this."))
                    BulletPoint(String(localized: "There's no rush. Take all the time you need."))
                    BulletPoint(String(localized: "Everything you enter here can be adjusted later in the app."))
                    BulletPoint(String(localized: "Want a hand? You can open our full Startup Guide here:"))
                }

                Button {
                    openURL(URL(string: "https://triodocs.org/startup-guide")!)
                } label: {
                    Text("https://triodocs.org/startup-guide")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(8)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal)
            }.padding()
                .background(Color.chart.opacity(0.65))
                .cornerRadius(10)
        }
    }
}
