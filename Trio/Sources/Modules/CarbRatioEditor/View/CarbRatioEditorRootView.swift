import Charts
import SwiftUI
import Swinject

extension CarbRatioEditor {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        var body: some View {
            TherapySettingsEditor.RootView(
                state: state,
                configureView: configureView,
                chartColor: Color.orange
            )
            .navigationTitle("Carb Ratios")
        }
    }
}
