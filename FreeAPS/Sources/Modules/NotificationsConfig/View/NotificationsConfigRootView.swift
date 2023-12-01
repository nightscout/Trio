import SwiftUI
import Swinject

extension NotificationsConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

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

                if #available(iOS 16.2, *) {
                    Section(
                        header: Text("Live Activity"),
                        footer: Text(
                            "Live activity displays blood glucose live on the lock screen and on the dynamic island (if available)"
                        )
                    ) {
                        Toggle("Show live activity", isOn: $state.useLiveActivity)
                    }
                }
            }
            .onAppear(perform: configureView)
            .navigationBarTitle("Notifications")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
