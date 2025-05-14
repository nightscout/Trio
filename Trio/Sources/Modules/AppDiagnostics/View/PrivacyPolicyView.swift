//
//  PrivacyPolicyView.swift
//  Trio
//
//  Created by Cengiz Deniz on 17.04.25.
//
import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.openURL) var openURL
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Introduction").font(.headline).bold().foregroundStyle(Color.primary)
                    Text(
                        "This Privacy Policy explains how we collect, use, and share information when you use Trio. We respect your privacy and are committed to protecting your personal data. Please read this Privacy Policy carefully to understand our practices regarding your personal data."
                    )

                    Divider()

                    Text("Information We Collect").font(.headline).bold().foregroundStyle(Color.primary)
                    Text("What We Do NOT Collect").foregroundStyle(Color.primary)

                    Text("For complete transparency, we want to clarify that Trio does not collect:")

                    VStack(alignment: .leading, spacing: 10) {
                        BulletPoint(String(localized: "Blood glucose (BG) readings"))
                        BulletPoint(String(localized: "Treatment data"))
                        BulletPoint(String(localized: "Total daily doses (TDD)"))
                        BulletPoint(String(localized: "Any health-related statistics or personal medical information"))
                        BulletPoint(String(localized: "Personal identifiable information such as name, address, or email"))
                    }

                    Text("Crash Reporting (Opt-In by default, with ability to Opt-Out)").foregroundStyle(Color.primary)
                    Text(
                        "Trio uses Google Firebase Crashlytics to collect crash reports. During the initial app setup (onboarding process), you will be asked to opt in to crash reporting. The onboarding process is the series of screens you see when first launching Trio that helps you set up the app."
                    )

                    Text("The following information may be sent to Crashlytics when Trio crashes:")

                    VStack(alignment: .leading, spacing: 10) {
                        BulletPoint(
                            String(
                                localized: "Time and date of the crash (example: \"Trio crashed on April 6, 2025 at 2:15 PM\")"
                            )
                        )
                        BulletPoint(
                            String(
                                localized: "Device state at the time of the crash (example: \"Trio was in the foreground\" or \"Battery level was 42%\")"
                            )
                        )
                        BulletPoint(
                            String(localized: "Stack trace information (technical information showing which line of code failed)")
                        )
                        BulletPoint(
                            String(localized: "Device model and OS version (example: \"iPhone 14 Pro running iOS 17.4.1\")")
                        )
                        BulletPoint(
                            String(
                                localized: "A generated unique identifier (a random code like \"A7B2C9D3\" that doesn't identify you personally)"
                            )
                        )
                    }

                    Text("Debug Symbols (dSYMs)").foregroundStyle(Color.primary)

                    Text(
                        "When we build the Trio app, we create special files called debug symbols (dSYMs) that help us read crash reports. Think of these like a decoder ring for crashes:"
                    )

                    Text(
                        "Without dSYMs, a crash might look like: \"Error at memory address 0x1234ABCD\". With dSYMs, we can see: \"Error in function 'calculateInsulin' at line 157\""
                    )

                    Text(
                        "These files only contain code-related information that helps us understand where crashes happen. They contain no personal information about you or how you use Trio."
                    )

                    Divider()

                    Text("How We Use Your Information").font(.headline).bold().foregroundStyle(Color.primary)

                    Text("We use anonymous crash report information exclusively to:")

                    VStack(alignment: .leading, spacing: 10) {
                        BulletPoint(String(localized: "Identify and fix bugs and crashes"))
                        BulletPoint(String(localized: "Improve Trio's stability"))
                    }

                    Text("We do not use this information for any other purpose, such as analytics, marketing, or user profiling.")

                    Divider()

                    Text("Data Sharing and Third-Party Services").font(.headline).bold().foregroundStyle(Color.primary)

                    Text("Crashlytics").foregroundStyle(Color.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(
                            "We use Google Firebase Crashlytics to collect and analyze crash reports. Crashlytics' privacy practices are governed by the Google Privacy Policy. For more information about how Crashlytics processes data, please visit their documentation."
                        )

                        Button {
                            openURL(URL(string: "https://policies.google.com/privacy")!)
                        } label: {
                            Text("Google Privacy Policy")
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(8)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal)
                    }

                    Text("Open Source Contributors").foregroundStyle(Color.primary)

                    Text(
                        "As an open source project, crash reports and debugging information may be visible to project contributors who help maintain and improve Trio. All contributors are expected to adhere to this privacy policy and handle any data responsibly."
                    )

                    Divider()

                    Text("Opting Out and Data Retention")

                    Text("You can opt out of crash reporting at any time through the Trio settings. If you opt out:")

                    VStack(alignment: .leading, spacing: 10) {
                        BulletPoint(String(localized: "No new crash data will be collected or sent to us"))
                        BulletPoint(
                            String(localized: "Previously collected crash data will still be retained for approximately 90 days")
                        )
                    }

                    Text(
                        "To avoid sending dSYMs to Crashlytics, you can delete the Trio target Build Phase script, titled \"Copy dSYMs to Crashlytics\"."
                    )

                    Divider()

                    Text("Your Rights").font(.headline).bold().foregroundStyle(Color.primary)

                    Text("You have certain rights regarding your information, including:")

                    VStack(alignment: .leading, spacing: 10) {
                        BulletPoint(String(localized: "The right to opt-out of crash reporting"))
                        BulletPoint(String(localized: "The right to request deletion of your data"))
                    }

                    Text(
                        "To opt-out of crash reporting, please see the section above for details about how to configure Trio to not record crash reports."
                    )

                    Text(
                        "The information we store is anonymous, so we are unable to look up information for a particular individual. However, our general data retention policy ensures that data older than 90 days is deleted, enabling us to accommodate data deletion requests by design despite having anonymous data."
                    )

                    Divider()

                    Text("Changes to This Privacy Policy").font(.headline).bold().foregroundStyle(Color.primary)

                    Text(
                        "We may update this Privacy Policy from time to time. We will notify you of any changes by posting the new Privacy Policy on this page and updating the \"Last Updated\" date."
                    )

                    Divider()

                    Text("Contact Us").font(.headline).bold().foregroundStyle(Color.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(
                            "If you have any questions about this Privacy Policy, please contact us on Discord, or send us an email."
                        ).multilineTextAlignment(.leading)

                        HStack(alignment: .center, spacing: 10) {
                            Button {
                                openURL(URL(string: "http://discord.triodocs.org/")!)
                            } label: {
                                Text("Trio Discord")
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.blue.opacity(0.2))
                                    .cornerRadius(8)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal)

                            Button {
                                openURL(URL(string: "mailto:trio.diy.diabetes@gmail.com")!)
                            } label: {
                                Text("Email us")
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.blue.opacity(0.2))
                                    .cornerRadius(8)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal)
                        }
                    }

                    Divider()

                    HStack {
                        Text("Last Updated:").bold()
                        Text("April 15, 2025")
                    }
                    .font(.headline).foregroundStyle(Color.primary)
                }
                .font(.footnote)
                .foregroundStyle(Color.secondary)
                .listRowBackground(Color.clear)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            }
            .scrollContentBackground(.hidden)
            .navigationBarTitle("Privacy Policy", displayMode: .inline)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Got it!").bold().frame(maxWidth: .infinity, minHeight: 30, alignment: .center)
            }
            .buttonStyle(.bordered)
            .padding([.top, .horizontal])
        }.ignoresSafeArea(edges: .top)
    }
}
