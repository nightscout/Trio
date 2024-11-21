import SwiftUI
import Swinject

extension WatchConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @Environment(\.colorScheme) var colorScheme
        var color: LinearGradient {
            colorScheme == .dark ? LinearGradient(
                gradient: Gradient(colors: [
                    Color.bgDarkBlue,
                    Color.bgDarkerDarkBlue
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
                :
                LinearGradient(
                    gradient: Gradient(colors: [Color.gray.opacity(0.1)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
        }

        var body: some View {
            Form {
                Section(
                    header: Text("Smartwatch Configuration"),
                    content: {
                        NavigationLink("Apple Watch", destination: WatchConfigAppleWatchView(resolver: resolver, state: state))
                        NavigationLink("Garmin", destination: WatchConfigGarminView(state: state))
                    }
                ).listRowBackground(Color.chart)
            }
            .scrollContentBackground(.hidden).background(color)
            .onAppear(perform: configureView)
            .navigationTitle("Watch")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
