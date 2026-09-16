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
                chartColor: Color.cyan,
                chartAccessibilityLabel: String(localized: "Insulin sensitivity profile chart, 24 hours")
            )
            .navigationTitle("Insulin Sensitivities")
        }
    }
}
