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
        @State var selectedVerboseHint: AnyView?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false
        @State private var displayPickerLowGlucose: Bool = false
        @State private var displayPickerHighGlucose: Bool = false

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
        @Environment(AppState.self) var appState

        var body: some View {
            List {
                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.notificationsPump,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Always Notify Pump")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: String(localized: "Always Notify Pump"),
                    miniHint: String(localized: "Always Notify Pump Warnings."),
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: ON").bold()
                        Text(
                            "With iOS Trio Notifications enabled, you can let Trio display most Pump Notifications in iOS Notification Center as a Banner, List and on the Lock Screen. It allows you to refer to Trio Information at a glance and troubleshoot any informational issue. Set iOS Notifications Banner Style to Persistent to display banners in the app until dismissed."
                        )
                        Text("If iOS Trio Notifications is disabled, Trio will display these messages in-app as a banner only.")
                        Text("An example of a Pump Warning is 'Pod Expiration Reminder'")
                    },
                    headerText: String(localized: "Trio Information Notifications")
                )
                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.notificationsCgm,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Always Notify CGM")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: String(localized: "Always Notify CGM"),
                    miniHint: String(localized: "Always Notify CGM Warnings."),
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: ON").bold()
                        Text(
                            "With iOS Trio Notifications enabled, you can let Trio display most CGM Notifications in iOS Notification Center as a Banner, List and on the Lock Screen. It allows you to refer to Trio Information at a glance and troubleshoot any informational issue. Set iOS Notifications Banner Style to Persistent to display banners in the app until dismissed."
                        )
                        Text("If iOS Trio Notifications is disabled, Trio will display these messages in-app as a banner only.")
                        Text("An example of a CGM Warning is 'Unable to open the app'")
                    }
                )
                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.notificationsCarb,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Always Notify Carb")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: String(localized: "Always Notify Carb"),
                    miniHint: String(localized: "Always Notify Carb Warnings."),
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: ON").bold()
                        Text(
                            "With iOS Trio Notifications enabled, you can let Trio display most Carb Notifications in iOS Notification Center as a Banner, List and on the Lock Screen. It allows you to refer to Trio Information at a glance and troubleshoot any informational issue. Set iOS Notifications Banner Style to Persistent to display banners in the app until dismissed."
                        )
                        Text("If iOS Trio Notifications is disabled, Trio will display these messages in-app as a banner only.")
                        Text("An example of a Carb Warning is 'Carbs required: 30 g'")
                    }
                )
                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.notificationsAlgorithm,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Always Notify Algorithm")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: String(localized: "Always Notify Algorithm"),
                    miniHint: String(localized: "Always Notify Algorithm Warnings."),
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: ON").bold()
                        Text(
                            "With iOS Trio Notifications enabled, you can let Trio display most Algorithm Notifications in iOS Notification Center as a Banner, List and on the Lock Screen. It allows you to refer to Trio Information at a glance and troubleshoot any informational issue. Set iOS Notifications Banner Style to Persistent to display banners in the app until dismissed."
                        )
                        Text("If iOS Trio Notifications is disabled, Trio will display these messages in-app as a banner only.")
                        Text(
                            "An example of an Algorithm Warning is 'Error: Invalid glucose: Not enough glucose data'"
                        )
                    }
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.glucoseBadge,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Show Glucose App Badge")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: String(localized: "Show Glucose App Badge"),
                    miniHint: String(localized: "Show your current glucose on Trio app icon."),
                    verboseHint: VStack(alignment: .leading, spacing: 10) {
                        Text("Default: OFF").bold()
                        Text(
                            "This will add your current glucose on the top right of your Trio icon as a red notification badge. Changing setting takes effect on next Glucose reading."
                        )
                    },
                    headerText: String(localized: "Various Glucose Notifications")
                )

                Section {
                    VStack {
                        Picker(
                            selection: $state.glucoseNotificationsOption,
                            label: Text("Glucose Notifications")
                        ) {
                            ForEach(GlucoseNotificationsOption.allCases) { selection in
                                Text(selection.displayName).tag(selection)
                            }
                        }.padding(.top)

                        HStack(alignment: .center) {
                            Text(
                                "Choose glucose notifications option. See hint for more details."
                            )
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                            Spacer()
                            Button(
                                action: {
                                    hintLabel = String(localized: "Glucose Notifications")
                                    selectedVerboseHint =
                                        AnyView(
                                            VStack(alignment: .leading, spacing: 10) {
                                                Text(
                                                    "Set the Glucose Notifications Option. Descriptions for each option found below."
                                                )
                                                VStack(alignment: .leading, spacing: 5) {
                                                    Text("Disabled:").bold()
                                                    Text("No Glucose Notifications will be triggered.")
                                                }
                                                VStack(alignment: .leading, spacing: 5) {
                                                    Text("Always:").bold()
                                                    Text(
                                                        "A notification will be triggered every time your glucose is updated in Trio."
                                                    )
                                                }
                                                VStack(alignment: .leading, spacing: 5) {
                                                    Text("Only Alarm Limits:").bold()
                                                    Text(
                                                        "A notification will be triggered only when glucose levels are below the LOW limit or above the HIGH limit, as specified in Glucose Alarm Limits below."
                                                    )
                                                }
                                            }
                                        )
                                    shouldDisplayHint.toggle()
                                },
                                label: {
                                    HStack {
                                        Image(systemName: "questionmark.circle")
                                    }
                                }
                            ).buttonStyle(BorderlessButtonStyle())
                        }.padding(.top)
                    }.padding(.bottom)
                }.listRowBackground(Color.chart)

                if state.glucoseNotificationsOption != GlucoseNotificationsOption.disabled {
                    self.lowAndHighGlucoseAlertSection
                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.addSourceInfoToGlucoseNotifications,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = String(localized: "Add Glucose Source to Alarm")
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: String(localized: "Add Glucose Source to Alarm"),
                        miniHint: String(localized: "Source of the glucose reading will be added to the notification."),
                        verboseHint: VStack(alignment: .leading, spacing: 10) {
                            Text("Default: OFF").bold()
                            Text("The source of the glucose reading will be added to the notification.")
                        }
                    )
                }
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
            .navigationBarTitle("Trio Notifications")
            .navigationBarTitleDisplayMode(.automatic)
        }

        var lowAndHighGlucoseAlertSection: some View {
            Section {
                VStack {
                    VStack {
                        HStack {
                            Text("Low Glucose Alarm Limit")

                            Spacer()

                            Group {
                                Text(
                                    state.units == .mgdL ? state.lowGlucose.description : state.lowGlucose.formattedAsMmolL
                                )
                                .foregroundColor(!displayPickerLowGlucose ? .primary : .accentColor)

                                Text(state.units == .mgdL ? " mg/dL" : " mmol/L").foregroundColor(.secondary)
                            }
                        }
                        .onTapGesture {
                            displayPickerLowGlucose.toggle()
                        }
                    }
                    .padding(.top)

                    if displayPickerLowGlucose {
                        let setting = PickerSettingsProvider.shared.settings.lowGlucose

                        Picker(selection: $state.lowGlucose, label: Text("")) {
                            ForEach(
                                PickerSettingsProvider.shared.generatePickerValues(from: setting, units: state.units),
                                id: \.self
                            ) { value in
                                let displayValue = state.units == .mgdL ? value.description : value.formattedAsMmolL
                                Text(displayValue).tag(value)
                            }
                        }
                        .pickerStyle(WheelPickerStyle())
                        .frame(maxWidth: .infinity)
                    }

                    VStack {
                        HStack {
                            Text("High Glucose Alarm Limit")

                            Spacer()

                            Group {
                                Text(
                                    state.units == .mgdL ? state.highGlucose.description : state.highGlucose.formattedAsMmolL
                                )
                                .foregroundColor(!displayPickerHighGlucose ? .primary : .accentColor)

                                Text(state.units == .mgdL ? " mg/dL" : " mmol/L").foregroundColor(.secondary)
                            }
                        }
                        .onTapGesture {
                            displayPickerHighGlucose.toggle()
                        }
                    }
                    .padding(.top)

                    if displayPickerHighGlucose {
                        let setting = PickerSettingsProvider.shared.settings.highGlucose
                        Picker(selection: $state.highGlucose, label: Text("")) {
                            ForEach(
                                PickerSettingsProvider.shared.generatePickerValues(from: setting, units: state.units),
                                id: \.self
                            ) { value in
                                let displayValue = state.units == .mgdL ? value.description : value.formattedAsMmolL
                                Text(displayValue).tag(value)
                            }
                        }
                        .pickerStyle(WheelPickerStyle())
                        .frame(maxWidth: .infinity)
                    }

                    HStack(alignment: .center) {
                        Text(
                            "Sets the lower and upper limit for glucose alarms."
                        )
                        .lineLimit(nil)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        Spacer()
                        Button(
                            action: {
                                hintLabel = String(localized: "Low and High Glucose Alarm Limits")
                                selectedVerboseHint =
                                    AnyView(VStack(alignment: .leading, spacing: 10) {
                                        let low: Decimal = 70
                                        let high: Decimal = 180
                                        let labelLow = (state.units == .mgdL ? low.description : low.formattedAsMmolL) + " " +
                                            state.units.rawValue
                                        let labelHigh = (state.units == .mgdL ? high.description : high.formattedAsMmolL) + " " +
                                            state.units.rawValue
                                        Text("Low Default: " + labelLow).bold()
                                        Text("High Default: " + labelHigh).bold()
                                        VStack(alignment: .leading, spacing: 10) {
                                            Text(
                                                "These two settings determine the range outside of which you will be notified via push notifications."
                                            )
                                            Text(
                                                "If your CGM readings are below the Low value or above the High value, you will receive a glucose alarm."
                                            )
                                        }
                                    })
                                shouldDisplayHint.toggle()
                            },
                            label: {
                                HStack {
                                    Image(systemName: "questionmark.circle")
                                }
                            }
                        ).buttonStyle(BorderlessButtonStyle())
                    }.padding(.top)
                }.padding(.bottom)
            }.listRowBackground(Color.chart)
        }
    }
}
