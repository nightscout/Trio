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
                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.glucoseBadge,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Show Glucose App Badge"
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: "Show Glucose App Badge",
                    miniHint: "Show your current glucose on Trio app icon",
                    verboseHint: VStack(spacing: 10) {
                        Text("Default: OFF").bold()
                        Text("This will add your current glucose on the top right of your Trio icon as a red notification badge.")
                    },
                    headerText: "Various Glucose Notifications"
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.glucoseNotificationsAlways,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Always Notify Glucose"
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: "Always Notify Glucose",
                    miniHint: "Trigger a notification every time your glucose is updated",
                    verboseHint: VStack {
                        Text("Default: OFF").bold()
                        Text("A notification will be triggered every time your glucose is updated in Trio.")
                    }
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.useAlarmSound,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Play Alarm Sound"
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: "Play Alarm Sound",
                    miniHint: "Alarm with every Trio notification",
                    verboseHint: VStack(spacing: 10) {
                        Text("Default: OFF").bold()
                        Text("This will cause a sound to be triggered by every Trio notification.")
                    }
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.addSourceInfoToGlucoseNotifications,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Add Glucose Source to Alarm"
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: "Add Glucose Source to Alarm",
                    miniHint: "Source of the glucose reading will be added to the notification",
                    verboseHint: VStack(spacing: 10) {
                        Text("Default: OFF").bold()
                        Text("The source of the glucose reading will be added to the notification.")
                    }
                )

                self.lowAndHighGlucoseAlertSection
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
            .navigationBarTitle("Glucose Notifications")
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

                    HStack(alignment: .top) {
                        Text(
                            "Sets the lower and upper limit for glucose alarms"
                        )
                        .lineLimit(nil)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        Spacer()
                        Button(
                            action: {
                                hintLabel = "Low and High Glucose Alarm Limits"
                                selectedVerboseHint =
                                    AnyView(VStack(spacing: 10) {
                                        Text("Low Default: 70 mg/dL").bold()
                                        Text("High Default: 180 mg/dL").bold()
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
