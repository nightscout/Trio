import SwiftUI
import Swinject

extension QuickPickTreatmentsConfig {
    struct RootView: BaseView {
        let resolver: Resolver

        @StateObject var state = StateModel()

        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: AnyView?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            List {
                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.enableQuickPickTreatments,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Enable Quick-Pick Treatments")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: String(localized: "Enable Quick-Pick Treatments"),
                    miniHint: String(localized: "Long-press the + button on the home screen to enact a quick-pick treatment."),
                    verboseHint: VStack(alignment: .leading, spacing: 10) {
                        Text("Default: OFF").bold()
                        Text(
                            "When enabled, long-pressing the + button on the home screen opens a Quick-Pick Treatments sheet. It suggests up to three bolus amounts and, if you have carb history, up to three carb amounts based on what you typically enter at this time of day, weighted by recency and day type (weekday vs. weekend)."
                        )
                        Text(
                            "Tap a bolus amount, a carb amount, or both, then slide to confirm. Face ID or Touch ID is always required before a bolus is enacted."
                        )
                    }
                )
            }
            .listSectionSpacing(sectionSpacing)
            .sheet(isPresented: $shouldDisplayHint) {
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    shouldDisplayHint: $shouldDisplayHint,
                    hintLabel: hintLabel ?? "",
                    hintText: selectedVerboseHint ?? AnyView(EmptyView()),
                    sheetTitle: String(localized: "Help", comment: "Help sheet title")
                )
            }
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationBarTitle("Quick-Pick Treatments")
            .navigationBarTitleDisplayMode(.automatic)
            .settingsHighlightScroll()
        }
    }
}
