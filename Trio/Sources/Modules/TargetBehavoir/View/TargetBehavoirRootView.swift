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
        @State private var showAutosensMaxAlert = false

        @Environment(\.colorScheme) var colorScheme
        @EnvironmentObject var appIcons: Icons
        @Environment(AppState.self) var appState

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
                            hintLabel = String(
                                localized:
                                "High Temp Target Raises Sensitivity",
                                comment: "High Temp Target Raises Sensitivity"
                            )
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: String(
                        localized:
                        "High Temp Target Raises Sensitivity",
                        comment: "High Temp Target Raises Sensitivity"
                    ),
                    miniHint: String(
                        localized: "Increase sensitivity when glucose is above target if a manual Temp Target > \(state.units == .mgdL ? "100" : 100.formattedAsMmolL) \(state.units.rawValue) is set."
                    ),
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: OFF").bold()
                        Text(
                            "When this feature is enabled, manually setting a temporary target above \(state.units == .mgdL ? "100" : 100.formattedAsMmolL) \(state.units.rawValue) will decrease the Autosens Ratio used for ISF and basal adjustments, resulting in less insulin delivered overall. This scales with the temporary target set; the higher the temp target, the lower the Autosens Ratio used."
                        )
                        Text(
                            "If Half Basal Exercise Target is set to \(state.units == .mgdL ? "160" : 160.formattedAsMmolL) \(state.units.rawValue), a temp target of \(state.units == .mgdL ? "120" : 120.formattedAsMmolL) \(state.units.rawValue) uses an Autosens Ratio of 0.75. A temp target of \(state.units == .mgdL ? "140" : 140.formattedAsMmolL) \(state.units.rawValue) uses an Autosens Ratio of 0.6."
                        )
                        Text("Note: The effect of this can be adjusted with the Half Basal Exercise Target")
                    },
                    headerText: String(localized: "Algorithmic Target Settings")
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: effectiveLowTTLowersSensBinding,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(
                                localized:
                                "Low Temp Target Lowers Sensitivity",
                                comment: "Low Temp Target Lowers Sensitivity"
                            )
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: String(
                        localized:
                        "Low Temp Target Lowers Sensitivity",
                        comment: "Low Temp Target Lowers Sensitivity"
                    ),
                    miniHint: String(
                        localized: "Decrease sensitivity when glucose is below target if a manual Temp Target < \(state.units == .mgdL ? "100" : 100.formattedAsMmolL) \(state.units.rawValue) is set."
                    ),
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: OFF").bold()
                        Text(
                            "When this feature is enabled, setting a temporary target below \(state.units == .mgdL ? "100" : 100.formattedAsMmolL) \(state.units.rawValue) will increase the Autosens Ratio used for ISF and basal adjustments, resulting in more insulin delivered overall. This scales with the temporary target set; the lower the Temp Target, the higher the Autosens Ratio used. It requires Algorithm Settings > Autosens > Autosens Max to be set to > 100% to work."
                        )
                        Text(
                            "If Half Basal Exercise Target is \(state.units == .mgdL ? "160" : 160.formattedAsMmolL) \(state.units.rawValue), a Temp Target of \(state.units == .mgdL ? "95" : 95.formattedAsMmolL) \(state.units.rawValue) uses an Autosens Ratio of 1.09. A Temp Target of \(state.units == .mgdL ? "85" : 85.formattedAsMmolL) \(state.units.rawValue) uses an Autosens Ratio of 1.33."
                        )
                        Text("Note: The effect of this can be adjusted with the Half Basal Exercise Target")
                    }
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.sensitivityRaisesTarget,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Sensitivity Raises Target", comment: "Sensitivity Raises Target")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: String(localized: "Sensitivity Raises Target", comment: "Sensitivity Raises Target"),
                    miniHint: String(localized: "Raise target glucose when Autosens Ratio is less than 1."),
                    verboseHint: VStack(alignment: .leading, spacing: 10) {
                        Text("Default: OFF").bold()
                        Text(
                            "Enabling this feature causes Trio to automatically raise the targeted glucose if it detects an increase in insulin sensitivity from your baseline."
                        )
                    }
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.resistanceLowersTarget,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Resistance Lowers Target", comment: "Resistance Lowers Target")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: String(localized: "Resistance Lowers Target", comment: "Resistance Lowers Target"),
                    miniHint: String(localized: "Lower target glucose when Autosens Ratio is greater than 1."),
                    verboseHint: VStack(alignment: .leading, spacing: 10) {
                        Text("Default: OFF").bold()
                        Text(
                            "Enabling this feature causes Trio to automatically reduce the targeted glucose if it detects a decrease in sensitivity (resistance) from your baseline."
                        )
                    }
                )

                SettingInputSection(
                    decimalValue: $state.halfBasalExerciseTarget,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Half Basal Exercise Target", comment: "Half Basal Exercise Target")
                        }
                    ),
                    units: state.units,
                    type: .decimal("halfBasalExerciseTarget"),
                    label: String(localized: "Half Basal Exercise Target", comment: "Half Basal Exercise Target"),
                    miniHint: String(localized: "Scales down your basal rate to 50% at this value."),
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text(
                            "Default: \(state.units == .mgdL ? "160" : 160.formattedAsMmolL) \(state.units.rawValue)"
                        )
                        .bold()
                        Text(
                            "The Half Basal Exercise Target allows you to scale down your basal insulin during exercise or scale up your basal insulin when eating soon when a temporary glucose target is set."
                        )
                        Text(
                            "For example, at a temp target of \(state.units == .mgdL ? "160" : 160.formattedAsMmolL) \(state.units.rawValue), your basal is reduced to 50%, but this scales depending on the target (e.g., 75% at \(state.units == .mgdL ? "120" : 120.formattedAsMmolL) \(state.units.rawValue), 60% at \(state.units == .mgdL ? "140" : 140.formattedAsMmolL) \(state.units.rawValue))."
                        )
                        Text(
                            "Note: This setting is only utilized if the settings \"Low Temp Target Lowers Sensitivity\" OR \"High Temp Target Raises Sensitivity\" are enabled."
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
            .alert(
                "Cannot Enable This Setting",
                isPresented: $showAutosensMaxAlert
            ) {
                // Alert button(s). For a single button:
                Button("Got it!", role: .cancel) {}
            } message: {
                Text(
                    "This feature cannot be enabled unless Algorithm Settings > Autosens > Autosens Max is set higher than 100%."
                )
            }
            .navigationTitle("Target Behavior")
            .navigationBarTitleDisplayMode(.automatic)
        }

        private var effectiveLowTTLowersSensBinding: Binding<Bool> {
            Binding(
                get: { state.autosensMax > 1 && state.lowTemptargetLowersSensitivity },
                set: { newValue in
                    if newValue, state.autosensMax <= 1 {
                        showAutosensMaxAlert = true
                    } else {
                        state.lowTemptargetLowersSensitivity = newValue
                    }
                }
            )
        }
    }
}
