import SwiftUI
import Swinject

extension WatchConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState
        @State private var smartwatchSheet: SmartwatchSheet?
        @State private var smartwatchRevision = 0

        var body: some View {
            List {
                Section(
                    header: Text("Smartwatch Configuration"),
                    content: {
                        NavigationLink("Apple Watch", destination: WatchConfigAppleWatchView(resolver: resolver, state: state))
                        NavigationLink("Garmin", destination: WatchConfigGarminView(state: state))
                    }
                ).listRowBackground(Color.chart)
                // Rebuilt when a watch is added or removed.
                WatchConfigSmartwatchSections(resolver: resolver, sheet: $smartwatchSheet)
                    .id(smartwatchRevision)
            }
            .smartwatchSheets(resolver: resolver, sheet: $smartwatchSheet, revision: $smartwatchRevision)
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationTitle("Watch")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
