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
                                "High Temp Target Raises Sensitivity",
                                comment: "High Temp Target Raises Sensitivity"
                            )
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: NSLocalizedString(
                        "High Temp Target Raises Sensitivity",
                        comment: "High Temp Target Raises Sensitivity"
                    ),
                    miniHint: "A Temp Target > 110 mg/dL increases sensitivity when glucose is above target",
                    verboseHint: VStack(spacing: 10) {
                        Text("Default: OFF").bold()
                        VStack(alignment: .leading, spacing: 10) {
                            Text(
                                "When this feature is enabled, setting a temporary target above 110 mg/dL will decrease the Autosens Ratio used for ISF and basal adjustments, resulting in less insulin delivered overall. This scales with the temporary target set; the higher the temp target, the lower the Autosens Ratio used."
                            )
                            Text(
                                "If Half Basal Exercise Target is set to 160, a temp target of 120 mg/dL uses an Autosens Ratio of 0.75. A temp target of 140 mg/dL uses an Autosens Ratio of 0.6."
                            )
                            Text("Note: The effect of this can be adjusted with the Half Basal Exercise Target")
                        }
                    },
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
                                "Low Temp Target Lowers Sensitivity",
                                comment: "Low Temp Target Lowers Sensitivity"
                            )
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: NSLocalizedString(
                        "Low Temp Target Lowers Sensitivity",
                        comment: "Low Temp Target Lowers Sensitivity"
                    ),
                    miniHint: "Temp Target < 100 mg/dL decreases sensitivity when glucose is below target",
                    verboseHint: VStack(spacing: 10) {
                        Text("Default: OFF").bold()
                        VStack(alignment: .leading, spacing: 10) {
                            Text(
                                "When this feature is enabled, setting a temporary target below 100 mg/dL will increase the Autosens Ratio used for ISF and basal adjustments, resulting in more insulin delivered overall. This scales with the temporary target set; the lower the Temp Target, the higher the Autosens Ratio used."
                            )
                            Text(
                                "If Half Basal Exercise Target is 160, a Temp Target of 95 mg/dL uses an Autosens Ratio of 1.09. A Temp Target of 85 mg/dL uses an Autosens Ratio of 1.33."
                            )
                            Text("Note: The effect of this can be adjusted with the Half Basal Exercise Target")
                        }
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
                            hintLabel = NSLocalizedString("Sensitivity Raises Target", comment: "Sensitivity Raises Target")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: NSLocalizedString("Sensitivity Raises Target", comment: "Sensitivity Raises Target"),
                    miniHint: "Automatically raise target glucose if sensitivity is detected",
                    verboseHint: VStack(spacing: 10) {
                        Text("Default: OFF").bold()
                        Text("Automatically increase target glucose if it detects an increase in sensitivity.")
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
                            hintLabel = NSLocalizedString("Resistance Lowers Target", comment: "Resistance Lowers Target")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: NSLocalizedString("Resistance Lowers Target", comment: "Resistance Lowers Target"),
                    miniHint: "Automatically lower target glucose if resistance is detected",
                    verboseHint: VStack(spacing: 10) {
                        Text("Default: OFF").bold()
                        Text(
                            "Enabling this feature causes Trio to automatically reduce the targeted glucose if it detects a decrease in sensitivity (resistance)."
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
                            hintLabel = NSLocalizedString("Half Basal Exercise Target", comment: "Half Basal Exercise Target")
                        }
                    ),
                    units: state.units,
                    type: .decimal("halfBasalExerciseTarget"),
                    label: NSLocalizedString("Half Basal Exercise Target", comment: "Half Basal Exercise Target"),
                    miniHint: "Scales down your basal rate to 50% at this value",
                    verboseHint: VStack(spacing: 10) {
                        Text("Default: 160 mg/dL (8.9 mmol/L)").bold()
                        VStack(alignment: .leading, spacing: 10) {
                            Text(
                                "The Half Basal Exercise Target allows you to scale down your basal insulin during exercise or scale up your basal insulin when eating soon when a temporary glucose target is set."
                            )
                            Text(
                                "For example, at a temp target of 160 mg/dL, your basal is reduced to 50%, but this scales depending on the target (e.g., 75% at 120 mg/dL, 60% at 140 mg/dL)."
                            )
                            Text(
                                "Note: This setting is only utilized if the settings \"Low Temp Target Lowers Sensitivity\" OR \"High Temp Target Raises Sensitivity\" are enabled."
                            )
                        }
                    }
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
