import SwiftUI
import Swinject

extension Main {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        private var modalScheduler: TrioModalAlertScheduler {
            resolver.resolve(TrioAlertManager.self)!.modalScheduler
        }

        var body: some View {
            router.view(for: .home)
                .sheet(item: $state.modal) { modal in
                    NavigationView { modal.view }
                        .navigationViewStyle(StackNavigationViewStyle())
                }
                .sheet(item: $state.secondaryModal) { wrapper in
                    wrapper.view
                }
                .trioAlerts(modalScheduler)
                .onAppear(perform: configureView)
                .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
        }
    }
}
