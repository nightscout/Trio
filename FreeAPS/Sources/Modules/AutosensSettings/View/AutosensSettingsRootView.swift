import SwiftUI
import Swinject

extension AutosensSettings {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()
        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: AnyView?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false

        @Environment(\.colorScheme) var colorScheme
        @EnvironmentObject var appIcons: Icons

        private var color: LinearGradient {
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
            List {
                SettingInputSection(
                    decimalValue: $state.autosensMax,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString("Autosens Max", comment: "Autosens Max")
                        }
                    ),
                    units: state.units,
                    type: .decimal("autosensMax"),
                    label: NSLocalizedString("Autosens Max", comment: "Autosens Max"),
                    miniHint:  """
                    The higher limit of the Autosens Ratio
                    Default: **120%**
                    """,
                    verboseHint: Text(
                        NSLocalizedString(
                            "Autosens Max sets the maximum Autosens Ratio used by Autosens, Dynamic ISF, Sigmoid Formula, and/or Autotune. The Autosens Ratio is used to calculate the amount of adjustment needed to basals, ISF, and CR. Increasing this value allows automatic adjustments of basal rates to be higher, ISF to be lower, and CR to be lower. This can result in more insulin given.",
                            comment: "Autosens Max"
                        )
                    ),
                    headerText: "Glucose Deviations Algorithm"
                )

                SettingInputSection(
                    decimalValue: $state.autosensMin,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString("Autosens Min", comment: "Autosens Min")
                        }
                    ),
                    units: state.units,
                    type: .decimal("autosensMin"),
                    label: NSLocalizedString("Autosens Min", comment: "Autosens Min"),
                    miniHint: """
                    The lower limit of the Autosens Ratio
                    Default: **80%**
                    """,
                    verboseHint: Text(NSLocalizedString(
                        """
                        Autosens Min sets the minimum Autosens Ratio used by Autosens, Dynamic ISF, Sigmoid Formula, and/or Autotune. 
                        The Autosens Ratio is used to calculate the amount of adjustment needed to basals, ISF, and CR.
                        Decreasing this value allows automatic adjustments of basal rates to be lower, ISF to be higher, and CR to be higher.
                        """,
                        comment: "Autosens Min")
                    )
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.rewindResetsAutosens,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString("Rewind Resets Autosens", comment: "Rewind Resets Autosens")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: NSLocalizedString("Rewind Resets Autosens", comment: "Rewind Resets Autosens"),
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: Text(
                        NSLocalizedString(
                            "This feature, enabled by default, resets the autosens ratio to neutral when you rewind your pump, on the assumption that this corresponds to a probable site change. Autosens will begin learning sensitivity anew from the time of the rewind, which may take up to 6 hours. If you usually rewind your pump independently of site changes, you may want to consider disabling this feature.",
                            comment: "Rewind Resets Autosens"
                        )
                    )
                )
            }
            .sheet(isPresented: $shouldDisplayHint) {
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    shouldDisplayHint: $shouldDisplayHint,
                    hintLabel: hintLabel ?? "",
                    hintText: selectedVerboseHint ?? AnyView(EmptyView()),
                    sheetTitle: "Help"
                )
            }
            .scrollContentBackground(.hidden).background(color)
            .onAppear(perform: configureView)
            .navigationTitle("Autosens")
            .navigationBarTitleDisplayMode(.automatic)
            .onDisappear {
                state.saveIfChanged()
            }
        }
    }
}
