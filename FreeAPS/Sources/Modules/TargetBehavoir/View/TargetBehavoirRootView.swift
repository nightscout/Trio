import SwiftUI
import Swinject

extension TargetBehavoir {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
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
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.highTemptargetRaisesSensitivity,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString(
                                "High Temptarget Raises Sensitivity",
                                comment: "High Temptarget Raises Sensitivity"
                            )
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: NSLocalizedString(
                        "High Temptarget Raises Sensitivity",
                        comment: "High Temptarget Raises Sensitivity"
                    ),
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: Text(
                        NSLocalizedString(
                            "Defaults to false. When set to true, raises sensitivity (lower sensitivity ratio) for temp targets set to >= 111. Synonym for exercise_mode. The higher your temp target above 110 will result in more sensitive (lower) ratios, e.g., temp target of 120 results in sensitivity ratio of 0.75, while 140 results in 0.6 (with default halfBasalTarget of 160).",
                            comment: "High Temptarget Raises Sensitivity"
                        )
                    ),
                    headerText: "Algorithmic Target Settings"
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.lowTemptargetLowersSensitivity,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString(
                                "Low Temptarget Lowers Sensitivity",
                                comment: "Low Temptarget Lowers Sensitivity"
                            )
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: NSLocalizedString(
                        "Low Temptarget Lowers Sensitivity",
                        comment: "Low Temptarget Lowers Sensitivity"
                    ),
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: Text(
                        NSLocalizedString(
                            "Defaults to false. When set to true, can lower sensitivity (higher sensitivity ratio) for temptargets <= 99. The lower your temp target below 100 will result in less sensitive (higher) ratios, e.g., temp target of 95 results in sensitivity ratio of 1.09, while 85 results in 1.33 (with default halfBasalTarget of 160).",
                            comment: "Low Temptarget Lowers Sensitivity"
                        )
                    )
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.sensitivityRaisesTarget,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString("Sensitivity Raises Target", comment: "Sensitivity Raises Target")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: NSLocalizedString("Sensitivity Raises Target", comment: "Sensitivity Raises Target"),
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: Text(
                        NSLocalizedString(
                            "When true, raises BG target when autosens detects sensitivity",
                            comment: "Sensitivity Raises Target"
                        )
                    )
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.resistanceLowersTarget,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString("Resistance Lowers Target", comment: "Resistance Lowers Target")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: NSLocalizedString("Resistance Lowers Target", comment: "Resistance Lowers Target"),
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: Text(
                        NSLocalizedString(
                            "Defaults to false. When true, will lower BG target when autosens detects resistance",
                            comment: "Resistance Lowers Target"
                        )
                    )
                )

                SettingInputSection(
                    decimalValue: $state.halfBasalExerciseTarget,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = NSLocalizedString("Half Basal Exercise Target", comment: "Half Basal Exercise Target")
                        }
                    ),
                    units: state.units,
                    type: .decimal("halfBasalExerciseTarget"),
                    label: NSLocalizedString("Half Basal Exercise Target", comment: "Half Basal Exercise Target"),
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: Text(
                        NSLocalizedString(
                            "Set to a number, e.g. 160, which means when temp target is 160 mg/dL, run 50% basal at this level (120 = 75%; 140 = 60%). This can be adjusted, to give you more control over your exercise modes.",
                            comment: "Half Basal Exercise Target"
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
            .navigationTitle("Target Behavior")
            .navigationBarTitleDisplayMode(.automatic)
            .onDisappear {
                state.saveIfChanged()
            }
        }
    }
}
