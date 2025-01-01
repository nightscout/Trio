import LibreTransmitter
import SwiftUI
import Swinject

extension LibreConfig {
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
            Group {
                if state.configured, let manager = state.source.manager {
                    LibreTransmitterSettingsView(
                        manager: manager,
                        glucoseUnit: state.unit
                    ) {
                        self.state.source.manager = nil
                        self.state.configured = false
                    } completion: {
                        state.hideModal()
                    }
                } else {
                    LibreTransmitterSetupView { manager in
                        self.state.source.manager = manager
                        self.state.configured = true
                    } completion: {
                        state.hideModal()
                    }
                }
            }
            .scrollContentBackground(.hidden).background(color)
            .navigationBarTitle("")
            .navigationBarHidden(true)
            .onAppear(perform: configureView)
        }
    }
}
