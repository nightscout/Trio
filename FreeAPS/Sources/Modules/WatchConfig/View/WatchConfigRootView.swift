import SwiftUI
import Swinject

extension WatchConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            Form {
                Section(
                    header: Text("Smartwatch Configuration"),
                    content: {
                        NavigationLink("Apple Watch", destination: WatchConfigAppleWatchView(state: state))
                        NavigationLink("Garmin", destination: WatchConfigGarminView(state: state))
                    }
                ).listRowBackground(Color.chart)
            }
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationTitle("Watch")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
