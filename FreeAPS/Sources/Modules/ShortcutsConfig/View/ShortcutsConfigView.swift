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
                Section(header: Text("Shortcuts")) {
                    Text(
                        "The application lets you create automations using shortcuts. Go to the Shortcuts application to create new automations."
                    )
                    Button("Open Shortcuts app") {
                        openShortcutsApp()
                    }
                }

                Section(header: Text("Options")) {
                    Toggle("Allows to bolus with shortcuts", isOn: $state.allowBolusByShortcuts)

                    Picker(
                        selection: $state.maxBolusByShortcuts,
                        label: Text("Method to limit the bolus amount")
                    ) {
                        ForEach(BolusShortcutLimit.allCases) { v in
                            v != .noAllowed ? Text(v.displayName).tag(v) : nil
                            // Text(v.displayName).tag(v)
                        }
                    }
                    .disabled(!state.allowBolusByShortcuts)
                }
            }
            .onAppear(perform: configureView)
            .navigationTitle("Shortcuts config")
            .navigationBarTitleDisplayMode(.automatic)
        }

        private func openShortcutsApp() {
            let shortcutsURL = URL(string: "shortcuts://")!

            if UIApplication.shared.canOpenURL(shortcutsURL) {
                UIApplication.shared.open(shortcutsURL, options: [:], completionHandler: { success in
                    if !success {
                        state.router.alertMessage
                            .send(MessageContent(content: "Unable to open the app", type: .warning))
                    }
                })
            } else {
                router.alertMessage
                    .send(MessageContent(content: "Unable to open the app", type: .warning))
            }
        }
    }
}
