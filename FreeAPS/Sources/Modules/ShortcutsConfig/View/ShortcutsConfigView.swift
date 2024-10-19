import Combine
import SwiftUI
import Swinject
import UIKit

extension ShortcutsConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        var body: some View {
            Form {
                Section(header: Text("Shortcuts", tableName: "ShortcutsDetail")) {
                    Text(
                        "The application lets you create automations using shortcuts. Go to the Shortcuts application to create new automations.",
                        tableName: "ShortcutsDetail"
                    )
                    Button(String(localized: "Open Shortcuts app", table: "ShortcutsDetail")) {
                        openShortcutsApp()
                    }
                }

                Section(header: Text("Options", tableName: "ShorcutsDetail")) {
                    Toggle(
                        String(localized: "Allow bolusing with shortcuts", table: "ShortcutsDetail"),
                        isOn: $state.allowBolusByShortcuts
                    )

                    Picker(
                        selection: $state.maxBolusByShortcuts,
                        label: Text("Limit bolus from shortcuts to", tableName: "ShortcutsDetail")
                    ) {
                        ForEach(BolusShortcutLimit.allCases) { v in
                            v != .notAllowed ? Text(v.displayName).tag(v) : nil
                            // Text(v.displayName).tag(v)
                        }
                    }
                    .disabled(!state.allowBolusByShortcuts)
                }
            }
            .onAppear(perform: configureView)
            .navigationTitle(String(localized: "Shortcuts config", table: "ShortcutsDetail"))
            .navigationBarTitleDisplayMode(.automatic)
        }

        private func openShortcutsApp() {
            let shortcutsURL = URL(string: "shortcuts://")!

            if UIApplication.shared.canOpenURL(shortcutsURL) {
                UIApplication.shared.open(shortcutsURL, options: [:], completionHandler: { success in
                    if !success {
                        state.router.alertMessage
                            .send(MessageContent(
                                content: String(localized: "Unable to open the app", table: "ShortcutsDetail"),
                                type: .warning
                            ))
                    }
                })
            } else {
                router.alertMessage
                    .send(MessageContent(
                        content: String(localized: "Unable to open the app", table: "ShortcutsDetail"),
                        type: .warning
                    ))
            }
        }
    }
}
