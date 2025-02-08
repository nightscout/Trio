import SwiftUI
import Swinject

extension Main {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            router.view(for: .home)
                .sheet(isPresented: $state.isModalPresented) {
                    NavigationView { self.state.modal!.view }
                        .navigationViewStyle(StackNavigationViewStyle())
                }
                .sheet(isPresented: $state.isSecondaryModalPresented) {
                    state.secondaryModalView ?? EmptyView().asAny()
                }
                .onAppear(perform: configureView)
                .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
        }
    }
}
