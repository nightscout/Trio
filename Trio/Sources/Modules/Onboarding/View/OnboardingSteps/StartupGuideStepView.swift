//
//  StartupGuideStepView.swift
//  Trio
//
//  Created by Cengiz Deniz on 06.04.25.
//
import SwiftUI

struct StartupGuideStepView: View {
    @Environment(\.openURL) var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Before you begin…")
                .padding(.horizontal)
                .font(.title3)
                .bold()

            VStack(alignment: .leading, spacing: 10) {
                BulletPoint(String(localized: "Take a deep breath — you've got this."))
                BulletPoint(String(localized: "There's no rush. Take all the time you need."))
                BulletPoint(String(localized: "Everything you enter here can be adjusted later in the app."))
                BulletPoint(String(localized: "Want a hand? You can open our full Startup Guide here:"))

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
            }.padding(.horizontal)

            VStack(alignment: .leading, spacing: 10) {
                Text("Already using Trio and updating from an older version?").bold()
                BulletPoint(String(localized: "Your therapy settings, pump, and CGM configurations will be carried over."))
                BulletPoint(
                    String(
                        localized: "Your algorithm settings (previously called \"OpenAPS settings\") will be reset to defaults."
                    )
                )
                BulletPoint(String(localized: "We recommend reviewing them carefully — Trio will guide you step-by-step."))
            }.padding(.horizontal)

            HStack {
                Text("You can pause at any time. Just be aware: if you ")
                    + Text("force quit").bold()
                    + Text(" the app before finishing onboarding, ")
                    + Text("your progress will not be saved.").bold()
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal)
        }
    }
}
