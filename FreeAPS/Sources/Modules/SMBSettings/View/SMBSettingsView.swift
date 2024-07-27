import HealthKit
import LoopKit
import LoopKitUI
import SwiftUI
import Swinject

extension SMBSettings {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @State private var showHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: String?
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

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter
        }

        var body: some View {
            List {
                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.enableSMBAlways,
                    showHint: $showHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0
                            hintLabel = NSLocalizedString("Enable SMB Always", comment: "Enable SMB Always")
                        }
                    ),
                    type: .boolean,
                    label: NSLocalizedString("Enable SMB Always", comment: "Enable SMB Always"),
                    shortHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: "Enable SMB always bla bla bla",
                    headerText: "Super-Micro-Bolus",
                    footerText: nil
                )

                if state.enableSMBAlways {
                    SettingInputSection(
                        decimalValue: $state.maxDeltaBGthreshold,
                        booleanValue: $booleanPlaceholder,
                        showHint: $showHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0
                                hintLabel = NSLocalizedString("Max Delta-BG Threshold SMB", comment: "Max Delta-BG Threshold")
                            }
                        ),
                        type: .decimal,
                        label: NSLocalizedString("Max Delta-BG Threshold SMB", comment: "Max Delta-BG Threshold"),
                        shortHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                        verboseHint: "Max Delta BG bla bla bla",
                        headerText: nil,
                        footerText: nil
                    )

                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.enableSMBWithCOB,
                        showHint: $showHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0
                                hintLabel = NSLocalizedString("Enable SMB With COB", comment: "Enable SMB With COB")
                            }
                        ),
                        type: .boolean,
                        label: NSLocalizedString("Enable SMB With COB", comment: "Enable SMB With COB"),
                        shortHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                        verboseHint: "Enable SMB for COB bla bla bla bla",
                        headerText: nil,
                        footerText: nil
                    )
                }
            }
            .sheet(isPresented: $showHint) {
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    showHint: $showHint,
                    hintLabel: hintLabel ?? "",
                    hintText: selectedVerboseHint ?? "",
                    sheetTitle: "Hint"
                )
            }
            .scrollContentBackground(.hidden).background(color)
            .navigationTitle("SMB Settings")
            .navigationBarTitleDisplayMode(.automatic)
//            .onDisappear {
//                state.saveIfChanged()
//            }
        }
    }
}
