import HealthKit
import SwiftUI
import Swinject

extension Settings {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @State private var showShareSheet = false

        @Environment(\.colorScheme) var colorScheme

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
            Form {
                Section {
                    HStack(spacing: 15) {
                        Image(systemName: "circle")
                            .imageScale(.small)
                            .font(.system(size: 32))
                            .foregroundColor(Color.green)
                        Toggle("Closed loop", isOn: $state.closedLoop)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                } header: {
                    Text(
                        "iAPS v\(state.versionNumber) (\(state.buildNumber))\nBranch: \(state.branch) \(state.copyrightNotice)\nBuild Expires: \(Bundle.main.profileExpiration)"
                    )
                    .textCase(nil)
                }.listRowBackground(Color.chart)

                Section {
                    SettingsRowView(imageName: "chart.xyaxis.line", title: "Statistics", tint: Color.green, spacing: 10)
                        .navigationLink(to: .statistics, from: self)
                } header: { Text("Statistics") }.listRowBackground(Color.chart)

                Section {
                    SettingsRowViewCustomImage(imageName: "pod", title: "Pump")
                        .navigationLink(to: .pumpConfig, from: self)
                    SettingsRowViewCustomImage(imageName: "g6", title: "CGM")
                        .navigationLink(to: .cgm, from: self)
                    SettingsRowView(imageName: "applewatch.watchface", title: "Watch", tint: Color.primary, spacing: 18)
                        .navigationLink(to: .watch, from: self)
                } header: { Text("Select Devices") }.listRowBackground(Color.chart)

                Section {
                    SettingsRowViewCustomImage(imageName: "owl", title: "Nightscout", frame: 32)
                        .navigationLink(to: .nighscoutConfig, from: self)
                    if HKHealthStore.isHealthDataAvailable() {
                        SettingsRowView(imageName: "heart.circle.fill", title: "Apple Health", tint: Color.red)
                            .navigationLink(to: .healthkit, from: self)
                    }
                    SettingsRowView(imageName: "message.circle.fill", title: "Notifications", tint: Color.blue)
                        .navigationLink(to: .notificationsConfig, from: self)
                } header: { Text("Services") }.listRowBackground(Color.chart)

                Section {
                    SettingsRowViewCustomImage(imageName: "pod", title: "Pump Settings")
                        .navigationLink(to: .pumpSettingsEditor, from: self)
                    SettingsRowView(imageName: "chart.bar.xaxis", title: "Basal Profile", tint: Color.insulin, spacing: 10)
                        .navigationLink(to: .basalProfileEditor, from: self)
                    SettingsRowView(imageName: "drop.fill", title: "Insulin Sensitivities", tint: Color.insulin, spacing: 22)
                        .navigationLink(to: .isfEditor, from: self)
                    SettingsRowView(imageName: "fork.knife.circle", title: "Carb Ratios", tint: Color.orange, spacing: 14)
                        .navigationLink(to: .crEditor, from: self)
                    SettingsRowView(imageName: "target", title: "Target Glucose", tint: Color.green, spacing: 14)
                        .navigationLink(to: .targetsEditor, from: self)
                } header: { Text("Configuration") }.listRowBackground(Color.chart)

                Section {
                    Text("OpenAPS").navigationLink(to: .preferencesEditor, from: self)
                    Text("Autotune").navigationLink(to: .autotuneConfig, from: self)
                } header: { Text("OpenAPS") }.listRowBackground(Color.chart)

                Section {
                    Text("UI/UX").navigationLink(to: .statisticsConfig, from: self)
                    Text("App Icons").navigationLink(to: .iconConfig, from: self)
                    Text("Bolus Calculator").navigationLink(to: .bolusCalculatorConfig, from: self)
                    Text("Fat And Protein Conversion").navigationLink(to: .fpuConfig, from: self)
                    Text("Dynamic ISF").navigationLink(to: .dynamicISF, from: self)
                } header: { Text("Extra Features") }.listRowBackground(Color.chart)

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
                        }

                        Group {
                            Text("Pump profile")
                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.pumpProfile), from: self)
                            Text("Profile")
                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.profile), from: self)
                            Text("Carbs")
                                .navigationLink(to: .configEditor(file: OpenAPS.Monitor.carbHistory), from: self)
                            Text("Announcements")
                                .navigationLink(to: .configEditor(file: OpenAPS.FreeAPS.announcements), from: self)
                            Text("Enacted announcements")
                                .navigationLink(to: .configEditor(file: OpenAPS.FreeAPS.announcementsEnacted), from: self)
                            Text("Autotune")
                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.autotune), from: self)
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
                } header: { Text("Developer") }.listRowBackground(Color.chart)

                Section {
                    Toggle("Animated Background", isOn: $state.animatedBackground)
                }.listRowBackground(Color.chart)

                Section {
                    Text("Share logs")
                        .onTapGesture {
                            showShareSheet = true
                        }
                }.listRowBackground(Color.chart)
            }.scrollContentBackground(.hidden).background(color)
                .sheet(isPresented: $showShareSheet) {
                    ShareSheet(activityItems: state.logItems())
                }
                .onAppear(perform: configureView)
                .navigationTitle("Menu")
                .navigationBarTitleDisplayMode(.large)
                .onDisappear(perform: { state.uploadProfileAndSettings(false) })
                .screenNavigation(self)
        }
    }
}
