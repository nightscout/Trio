import Charts
import SwiftUI
import Swinject

extension ISFEditor {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()

        var body: some View {
            TherapySettingsEditor.RootView(
                state: state,
                configureView: configureView,
                chartColor: Color.cyan
            )
            .navigationTitle("Insulin Sensitivities")
        }
    }
}
