import ActivityKit
import Combine
import SwiftUI
import Swinject

extension GlucoseNotificationSettings {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: String?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false
        @State var notificationsDisabled = false

        private var glucoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            if state.units == .mmolL {
                formatter.maximumFractionDigits = 1
            }
            formatter.roundingMode = .halfUp
            return formatter
        }

        private var carbsFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter
        }

        @Environment(\.colorScheme) var colorScheme

        var color: LinearGradient {
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
            Form {
                if !notificationsDisabled {
                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.glucoseBadge,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0
                                hintLabel = "Show Glucose App Badge"
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: "Show Glucose App Badge",
                        miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                        verboseHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                        headerText: "Various Glucose Notifications"
                    )
                }

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.glucoseNotificationsAlways,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0
                            hintLabel = "Always Notify Glucose"
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: "Always Notify Glucose",
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr."
                )

                if !notificationsDisabled {
                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.useAlarmSound,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0
                                hintLabel = "Play Alarm Sound"
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: "Play Alarm Sound",
                        miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                        verboseHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr."
                    )

                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.addSourceInfoToGlucoseNotifications,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0
                                hintLabel = "Add Glucose Source to Alarm"
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: "Add Glucose Source to Alarm",
                        miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                        verboseHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr."
                    )

                    Section {
                        HStack {
                            Text("Low Glucose Alarm Limit")
                            Spacer()
                            TextFieldWithToolBar(text: $state.lowGlucose, placeholder: "0", numberFormatter: glucoseFormatter)
                            Text(state.units.rawValue).foregroundColor(.secondary)
                        }.padding(.top)

                        HStack {
                            Text("High Glucose Alarm Limit")
                            Spacer()
                            TextFieldWithToolBar(text: $state.highGlucose, placeholder: "0", numberFormatter: glucoseFormatter)
                            Text(state.units.rawValue).foregroundColor(.secondary)
                        }

                        HStack(alignment: .top) {
                            Text(
                                "Set the lower and upper limit for glucose alarms. See hint for more details."
                            )
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                            Spacer()
                            Button(
                                action: {
                                    hintLabel = "Low and High Glucose Alarm Limits"
                                    selectedVerboseHint =
                                        "These two settings limit the range outside of which you will be notified via push notifications. If your CGM readings are below 'Low' or above 'High', you will receive a glucose alarm."
                                    shouldDisplayHint.toggle()
                                },
                                label: {
                                    HStack {
                                        Image(systemName: "questionmark.circle")
                                    }
                                }
                            ).buttonStyle(BorderlessButtonStyle())
                        }.padding(.vertical)
                    }
                    .listRowBackground(Color.chart)
                }
            }
            .sheet(isPresented: $shouldDisplayHint) {
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    shouldDisplayHint: $shouldDisplayHint,
                    hintLabel: hintLabel ?? "",
                    hintText: selectedVerboseHint ?? "",
                    sheetTitle: "Help"
                )
            }
            .onReceive(resolver.resolve(AlertPermissionsChecker.self)!.$notificationsDisabled, perform: {
                notificationsDisabled = $0
            })
            .scrollContentBackground(.hidden).background(color)
            .onAppear(perform: configureView)
            .navigationBarTitle("Glucose Notifications")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
