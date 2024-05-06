import ActivityKit
import Combine
import SwiftUI
import Swinject

extension NotificationsConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @State private var systemLiveActivitySetting: Bool = {
            if #available(iOS 16.1, *) {
                ActivityAuthorizationInfo().areActivitiesEnabled
            } else {
                false
            }
        }()

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
                    Color("Background_1"),
                    Color("Background_1"),
                    Color("Background_2")
                    // Color("Background_1")
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

        @ViewBuilder private func liveActivitySection() -> some View {
            if #available(iOS 16.2, *) {
                Section(
                    header: Text("Live Activity"),
                    footer: Text(
                        liveActivityFooterText()
                    ),
                    content: {
                        if !systemLiveActivitySetting {
                            Button("Open Settings App") {
                                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                            }
                        } else {
                            Toggle("Show Live Activity", isOn: $state.useLiveActivity)
                        }
                        Picker(
                            selection: $state.lockScreenView,
                            label: Text("Lock screen widget")
                        ) {
                            ForEach(LockScreenView.allCases) { selection in
                                Text(selection.displayName).tag(selection)
                            }
                        }
                    }
                )
                .onReceive(resolver.resolve(LiveActivityBridge.self)!.$systemEnabled, perform: {
                    self.systemLiveActivitySetting = $0
                })
            }
        }

        private func liveActivityFooterText() -> String {
            var footer =
                "Live activity displays blood glucose live on the lock screen and on the dynamic island (if available)"

            if !systemLiveActivitySetting {
                footer =
                    "Live activities are turned OFF in system settings. To enable live activities, go to Settings app -> Trio -> Turn live Activities ON.\n\n" +
                    footer
            }

            return footer
        }

        var body: some View {
            Form {
                Section(header: Text("Glucose")) {
                    Toggle("Show glucose on the app badge", isOn: $state.glucoseBadge)
                    Toggle("Always Notify Glucose", isOn: $state.glucoseNotificationsAlways)
                    Toggle("Also play alert sound", isOn: $state.useAlarmSound)
                    Toggle("Also add source info", isOn: $state.addSourceInfoToGlucoseNotifications)

                    HStack {
                        Text("Low")
                        Spacer()
                        DecimalTextField("0", value: $state.lowGlucose, formatter: glucoseFormatter)
                        Text(state.units.rawValue).foregroundColor(.secondary)
                    }

                    HStack {
                        Text("High")
                        Spacer()
                        DecimalTextField("0", value: $state.highGlucose, formatter: glucoseFormatter)
                        Text(state.units.rawValue).foregroundColor(.secondary)
                    }
                }

                Section(header: Text("Other")) {
                    HStack {
                        Text("Carbs Required Threshold")
                        Spacer()
                        DecimalTextField("0", value: $state.carbsRequiredThreshold, formatter: carbsFormatter)
                        Text("g").foregroundColor(.secondary)
                    }
                }

                liveActivitySection()
            }.scrollContentBackground(.hidden).background(color)
                .onAppear(perform: configureView)
                .navigationBarTitle("Notifications")
                .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
