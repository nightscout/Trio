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
                    miniHint: "A Temp Target > \(state.units == .mgdL ? "110" : 110.formattedAsMmol ?? "110") \(state.units.rawValue) increases sensitivity when glucose is above target.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: OFF").bold()
                        Text(
                            "When this feature is enabled, setting a temporary target above \(state.units == .mgdL ? "110" : 110.formattedAsMmol ?? "110") \(state.units.rawValue) will decrease the Autosens Ratio used for ISF and basal adjustments, resulting in less insulin delivered overall. This scales with the temporary target set; the higher the temp target, the lower the Autosens Ratio used."
                        )
                        Text(
                            "If Half Basal Exercise Target is set to \(state.units == .mgdL ? "160" : 160.formattedAsMmol ?? "160") \(state.units.rawValue), a temp target of \(state.units == .mgdL ? "120" : 120.formattedAsMmol ?? "120") \(state.units.rawValue) uses an Autosens Ratio of 0.75. A temp target of \(state.units == .mgdL ? "140" : 140.formattedAsMmol ?? "140") \(state.units.rawValue) uses an Autosens Ratio of 0.6."
                        )
                        Text("Note: The effect of this can be adjusted with the Half Basal Exercise Target")
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
                    miniHint: "Temp Target < \(state.units == .mgdL ? "100" : 100.formattedAsMmol ?? "100") \(state.units.rawValue) decreases sensitivity when glucose is below target.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: OFF").bold()
                        Text(
                            "When this feature is enabled, setting a temporary target below \(state.units == .mgdL ? "100" : 100.formattedAsMmol ?? "100") \(state.units.rawValue) will increase the Autosens Ratio used for ISF and basal adjustments, resulting in more insulin delivered overall. This scales with the temporary target set; the lower the Temp Target, the higher the Autosens Ratio used."
                        )
                        Text(
                            "If Half Basal Exercise Target is \(state.units == .mgdL ? "160" : 160.formattedAsMmol ?? "160") \(state.units.rawValue), a Temp Target of \(state.units == .mgdL ? "95" : 95.formattedAsMmol ?? "95") \(state.units.rawValue) uses an Autosens Ratio of 1.09. A Temp Target of \(state.units == .mgdL ? "85" : 85.formattedAsMmol ?? "85") \(state.units.rawValue) uses an Autosens Ratio of 1.33."
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
                            hintLabel = NSLocalizedString("Sensitivity Raises Target", comment: "Sensitivity Raises Target")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: NSLocalizedString("Sensitivity Raises Target", comment: "Sensitivity Raises Target"),
                    miniHint: "Automatically raise target glucose if sensitivity is detected.",
                    verboseHint: VStack(alignment: .leading, spacing: 10) {
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
                    miniHint: "Automatically lower target glucose if resistance is detected.",
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
                    miniHint: "Scales down your basal rate to 50% at this value.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text(
                            "Default: \(state.units == .mgdL ? "160" : 160.formattedAsMmol ?? "160") \(state.units.rawValue)"
                        )
                        .bold()
                        Text(
                            "The Half Basal Exercise Target allows you to scale down your basal insulin during exercise or scale up your basal insulin when eating soon when a temporary glucose target is set."
                        )
                        Text(
                            "For example, at a temp target of \(state.units == .mgdL ? "160" : 160.formattedAsMmol ?? "160") \(state.units.rawValue), your basal is reduced to 50%, but this scales depending on the target (e.g., 75% at \(state.units == .mgdL ? "120" : 120.formattedAsMmol ?? "120") \(state.units.rawValue), 60% at \(state.units == .mgdL ? "140" : 140.formattedAsMmol ?? "140") \(state.units.rawValue))."
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
