import HealthKit
import LoopKit
import LoopKitUI
import SwiftUI
import Swinject

extension Settings {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @State private var showShareSheet = false
        @StateObject private var viewModel = SettingsRootViewModel()

        var body: some View {
            Form {
                Section {
                    Toggle("Closed loop", isOn: $state.closedLoop)
                }
                header: {
                    Text(viewModel.headerText).textCase(nil)
                }

                Section {
                    Text("Pump").navigationLink(to: .pumpConfig, from: self)
                    Text("CGM").navigationLink(to: .cgm, from: self)
                    Text("Watch").navigationLink(to: .watch, from: self)
                } header: { Text("Devices") }

                Section {
                    Text("Nightscout").navigationLink(to: .nighscoutConfig, from: self)

                    NavigationLink(destination: TidepoolStartView(state: state)) {
                        Text("Tidepool")
                    }
                    if HKHealthStore.isHealthDataAvailable() {
                        Text("Apple Health").navigationLink(to: .healthkit, from: self)
                    }
                    Text("Notifications").navigationLink(to: .notificationsConfig, from: self)
                    Text("App Icons").navigationLink(to: .iconConfig, from: self)
                    Text("Statistics and Home View").navigationLink(to: .statisticsConfig, from: self)
                    Text("Shortcuts", tableName: "ShortcutsDetail").navigationLink(to: .shortcutsConfig, from: self)
                } header: { Text("Services") }

                Section {
                    Text("Preferences").navigationLink(to: .preferencesEditor, from: self)
                    Text("Pump Settings").navigationLink(to: .pumpSettingsEditor, from: self)
                    Text("Meal Settings").navigationLink(to: .fpuConfig, from: self)
                    Text("Basal Profile").navigationLink(to: .basalProfileEditor, from: self)
                    Text("Insulin Sensitivities").navigationLink(to: .isfEditor, from: self)
                    Text("Carb Ratios").navigationLink(to: .crEditor, from: self)
                    Text("Target Glucose").navigationLink(to: .targetsEditor, from: self)
                    Text("Autotune").navigationLink(to: .autotuneConfig, from: self)
                } header: { Text("Configuration") }

                Section {
                    Toggle("Debug options", isOn: $state.debugOptions)
                    if state.debugOptions {
                        Group {
                            HStack {
                                Text("NS Upload Profile and Settings")
                                Button("Upload") { state.uploadProfileAndSettings(true) }
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .buttonStyle(.borderedProminent)
                            }
                            // Commenting this out for now, as not needed and possibly dangerous for users to be able to nuke their pump pairing informations via the debug menu
                            // Leaving it in here, as it may be a handy functionality for further testing or developers.
                            // See https://github.com/nightscout/Trio/pull/277 for more information
//
//                            HStack {
//                                Text("Delete Stored Pump State Binary Files")
//                                Button("Delete") { state.resetLoopDocuments() }
//                                    .frame(maxWidth: .infinity, alignment: .trailing)
//                                    .buttonStyle(.borderedProminent)
//                            }
                        }
                        Group {
                            Text("Preferences")
                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.preferences), from: self)
                            Text("Pump Settings")
                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.settings), from: self)
                            Text("Autosense")
                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.autosense), from: self)
                            Text("Pump History")
                                .navigationLink(to: .configEditor(file: OpenAPS.Monitor.pumpHistory), from: self)
                            Text("Basal profile")
                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.basalProfile), from: self)
                            Text("Targets ranges")
                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.bgTargets), from: self)
                            Text("Temp targets")
                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.tempTargets), from: self)
                            Text("Meal")
                                .navigationLink(to: .configEditor(file: OpenAPS.Monitor.meal), from: self)
                        }

                        Group {
                            Text("Pump profile")
                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.pumpProfile), from: self)
                            Text("Profile")
                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.profile), from: self)
                            Text("Carbs")
                                .navigationLink(to: .configEditor(file: OpenAPS.Monitor.carbHistory), from: self)
                            Text("Enacted")
                                .navigationLink(to: .configEditor(file: OpenAPS.Enact.enacted), from: self)
                            Text("Announcements")
                                .navigationLink(to: .configEditor(file: OpenAPS.FreeAPS.announcements), from: self)
                            Text("Enacted announcements")
                                .navigationLink(to: .configEditor(file: OpenAPS.FreeAPS.announcementsEnacted), from: self)
                            Text("Autotune")
                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.autotune), from: self)
                            Text("Glucose")
                                .navigationLink(to: .configEditor(file: OpenAPS.Monitor.glucose), from: self)
                        }

                        Group {
                            Text("Target presets")
                                .navigationLink(to: .configEditor(file: OpenAPS.FreeAPS.tempTargetsPresets), from: self)
                            Text("Calibrations")
                                .navigationLink(to: .configEditor(file: OpenAPS.FreeAPS.calibrations), from: self)
                            Text("Middleware")
                                .navigationLink(to: .configEditor(file: OpenAPS.Middleware.determineBasal), from: self)
                            Text("Statistics")
                                .navigationLink(to: .configEditor(file: OpenAPS.Monitor.statistics), from: self)
                            Text("Edit settings json")
                                .navigationLink(to: .configEditor(file: OpenAPS.FreeAPS.settings), from: self)
                        }
                    }
                } header: { Text("Developer") }

                Section {
                    Toggle("Animated Background", isOn: $state.animatedBackground)
                }

                Section {
                    Text("Share logs")
                        .onTapGesture {
                            showShareSheet = true
                        }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(activityItems: state.logItems())
            }
            .onAppear(perform: configureView)
            .navigationTitle("Settings")
            .navigationBarItems(leading: Button("Close", action: state.hideSettingsModal))
            .navigationBarTitleDisplayMode(.automatic)
            .onDisappear(perform: { state.uploadProfileAndSettings(false) })
        }
    }
}
