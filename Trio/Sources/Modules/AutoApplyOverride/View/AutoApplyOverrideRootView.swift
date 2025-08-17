import CoreMotion
import SwiftUI
import Swinject

extension AutoApplyOverride {
    struct RootView: BaseView {
        typealias StateModelType = StateModel

        let resolver: Resolver
        @StateObject var state = StateModel()

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        private var dateFormatter: DateFormatter {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter
        }

        var body: some View {
            Form {
                Section(
                    header: Text("Auto Apply Override"),
                    footer: Text("Automatically apply override presets when physical activity is detected.")
                ) {
                    if !state.isActivityAvailable {
                        Label("Motion detection is not available on this device", systemImage: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                    } else if state.authorizationStatus == .denied {
                        Label(
                            "Motion permission denied. Enable in Settings > Privacy & Security > Motion & Fitness",
                            systemImage: "hand.raised"
                        )
                        .foregroundColor(.red)
                    } else {
                        Toggle("Enable Auto Apply Override", isOn: $state.isEnabled)
                    }
                }

                if state.isEnabled && state.isActivityAvailable && state.authorizationStatus != .denied {
                    Section(header: Text("Activity Types")) {
                        activityToggle(
                            title: "Cycling",
                            isEnabled: $state.cyclingEnabled,
                            selectedOverride: $state.cyclingOverride
                        )

                        activityToggle(
                            title: "Running",
                            isEnabled: $state.runningEnabled,
                            selectedOverride: $state.runningOverride
                        )

                        activityToggle(
                            title: "Walking",
                            isEnabled: $state.walkingEnabled,
                            selectedOverride: $state.walkingOverride
                        )
                    }

                    Section(
                        header: Text("Timing Settings"),
                        footer: Text(
                            "Activity must be detected for the start duration before applying an override. Override is removed after the stop duration when activity ends."
                        )
                    ) {
                        HStack {
                            Text("Start Duration")
                            Spacer()
                            Picker("", selection: $state.minimumDurationMinutes) {
                                ForEach([1, 3, 5, 10, 15], id: \.self) { minutes in
                                    Text("\(minutes) min").tag(minutes)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        HStack {
                            Text("Stop Duration")
                            Spacer()
                            Picker("", selection: $state.stopDurationMinutes) {
                                ForEach([1, 3, 5, 10, 15], id: \.self) { minutes in
                                    Text("\(minutes) min").tag(minutes)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    Section(
                        header: HStack {
                            Text("Activity Log")
                            Spacer()
                            if !state.activityLog.isEmpty {
                                Button("Clear") {
                                    state.clearActivityLog()
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                            }
                        }
                    ) {
                        if state.activityLog.isEmpty {
                            Text("A log will appear here upon first activation of this feature.")
                                .foregroundColor(.secondary)
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(state.activityLog.prefix(10), id: \.id) { entry in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(entry.activityType.displayName)
                                            .font(.headline)
                                        Spacer()
                                        if let endDate = entry.endDate {
                                            let duration = Calendar.current.dateComponents(
                                                [.minute],
                                                from: entry.startDate,
                                                to: endDate
                                            ).minute ?? 0
                                            Text("\(duration) min")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        } else {
                                            Text("Active")
                                                .font(.caption)
                                                .foregroundColor(.green)
                                        }
                                    }

                                    HStack {
                                        Text(dateFormatter.string(from: entry.startDate))
                                            .font(.caption)
                                            .foregroundColor(.secondary)

                                        if let endDate = entry.endDate {
                                            Text("→ \(dateFormatter.string(from: endDate))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()

                                        if let overrideName = entry.overrideName {
                                            Text(overrideName)
                                                .font(.caption)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 2)
                                                .background(Color.blue.opacity(0.2))
                                                .cornerRadius(4)
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Auto Apply Override")
            .navigationBarTitleDisplayMode(.large)
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear {
                configureView()
                state.refreshData()
            }
        }

        @ViewBuilder private func activityToggle(
            title: String,
            isEnabled: Binding<Bool>,
            selectedOverride: Binding<String>
        ) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(title, isOn: isEnabled)

                if isEnabled.wrappedValue {
                    HStack {
                        Spacer()
                        Picker("", selection: selectedOverride) {
                            Text("None").tag("")
                            ForEach(state.overridePresets, id: \.name) { preset in
                                Text(preset.name ?? "Unknown").tag(preset.name ?? "")
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.leading, 20)
                }
            }
        }
    }
}
