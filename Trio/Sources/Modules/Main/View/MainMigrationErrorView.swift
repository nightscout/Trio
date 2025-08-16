//
//  MainMigrationErrorView.swift
//  Trio
//
//  Created by Cengiz Deniz on 21.04.25.
//
import SwiftUI

extension Main {
    struct MainMigrationErrorView: View {
        let migrationErrors: [String]
        let onConfirm: () -> Void

        private let versionNumber = Bundle.main.releaseVersionNumber ?? String(localized: "Unknown")

        var body: some View {
            ZStack(alignment: .bottom) {
                LinearGradient(
                    gradient: Gradient(colors: [Color.bgDarkBlue, Color.bgDarkerDarkBlue]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack {
                        Spacer().frame(maxHeight: 20)

                        Image(.trioCircledNoBackground)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80, height: 80)
                            .shadow(color: Color.white.opacity(0.1), radius: 5, x: 0, y: 0)

                        Text("Trio v\(versionNumber)")
                            .fontWeight(.heavy)
                            .foregroundStyle(Color(red: 148 / 255, green: 102 / 255, blue: 234 / 255))
                            .padding(.vertical)

                        Spacer().frame(maxHeight: 20)

                        VStack(alignment: .leading, spacing: 20) {
                            Text("Oops! Some data didn’t make it over.").font(.title3).bold()

                            Text(
                                "While upgrading Trio to the new version, we ran into an issue transferring some of your historical data."
                            )
                            .multilineTextAlignment(.leading)

                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(migrationErrors, id: \.self) { message in
                                    BulletPoint(message)
                                }
                            }

                            Text(
                                "This means Trio may not have complete information about how much active insulin or carbs were still on board when you switched over."
                            )
                            .bold()

                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(Color.bgDarkBlue, Color.orange)
                                        .symbolRenderingMode(.palette)
                                    Text("To stay safe, we recommend:").foregroundStyle(Color.orange)
                                }.bold()

                                VStack(alignment: .leading, spacing: 10) {
                                    BulletPoint(
                                        String(
                                            localized: "Manually backdate some recent carbs or insulin you’ve entered in the last 6 to 8 hours."
                                        )
                                    )
                                    BulletPoint(
                                        String(
                                            localized: "Stay in open loop (no automated dosing) for a bit to help Trio catch up to keep you safe"
                                        )
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.orange, lineWidth: 2)
                            )
                            .cornerRadius(10)

                            Text(
                                "Trio is still fully functional and will adapt quickly — but your awareness right now helps it keep you safer."
                            )
                            .multilineTextAlignment(.leading)
                            .padding(.bottom)
                        }
                        .padding(.horizontal, 24)
                        .foregroundStyle(.white)
                    }
                }
                .padding(.bottom, 80)

                Button(action: onConfirm) {
                    Text("I understand! Proceed")
                        .frame(width: UIScreen.main.bounds.width - 60, height: 50)
                        .background(
                            Capsule()
                                .fill(Color.blue)
                        )
                        .foregroundColor(Color.white)
                }.padding(.bottom)
            }
        }
    }
}

struct MainMigrationErrorView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            Main.MainMigrationErrorView(
                migrationErrors: [
                    "Failed to import glucose history.",
                    "Failed to import pump history.",
                    "Failed to import carb history.",
                    "Failed to import algorithm data."
                ],
                onConfirm: { print("Proceed") }
            )
        }
    }
}
