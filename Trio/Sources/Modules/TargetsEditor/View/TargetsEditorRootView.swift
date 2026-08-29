import Charts
import SwiftUI
import Swinject

extension TargetsEditor {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        var body: some View {
            TherapySettingsEditor.RootView(
                state: state,
                configureView: configureView,
                chartColor: Color.green,
                chartShowsArea: false,
                chartYScale: (state.units == .mgdL ? Decimal(72) : Decimal(72).asMmolL) ...
                    (state.units == .mgdL ? Decimal(180) : Decimal(180).asMmolL)
            )
            .navigationTitle("Glucose Targets")
        }
    }
}
