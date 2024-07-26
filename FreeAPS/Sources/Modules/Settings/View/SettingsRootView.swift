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

        @State private var searchText: String = ""

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
            Form {
//                Section {
//                    Toggle("Closed loop", isOn: $state.closedLoop)
//                }
//                header: {
//                    Text(viewModel.headerText).textCase(nil)
//                }.listRowBackground(Color.chart)

                Section {
                    let buildDetails = BuildDetails.default
                    let versionNumber = Bundle.main.releaseVersionNumber ?? "Unknown"
                    let buildNumber = Bundle.main.buildVersionNumber ?? "Unknown"
                    let branch = buildDetails.branchAndSha

                    Group {
                        HStack {
                            Image(uiImage: UIImage(named: appIcons.appIcon.rawValue) ?? UIImage())
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 50, height: 50)
                                .padding(.trailing, 10)
                            VStack(alignment: .leading) {
                                Text("Trio v\(versionNumber) (\(buildNumber))")
                                    .font(.headline)
                                Text("Branch: \(branch)")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                if let expirationDate = buildDetails.calculateExpirationDate() {
                                    let formattedDate = DateFormatter.localizedString(
                                        from: expirationDate,
                                        dateStyle: .medium,
                                        timeStyle: .none
                                    )
                                    Text("\(buildDetails.expirationHeaderString): \(formattedDate)")
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        Text("Statistics").navigationLink(to: .statistics, from: self)
                    }
                }.listRowBackground(Color.chart)

                Section {
                    VStack {
                        Toggle("Closed Loop", isOn: $state.closedLoop)

                        Spacer()

                        (
                            Text("Running Trio in")
                                +
                                Text(" closed loop mode ").bold()
                                +
                                Text("requires an active CGM session sensor session and a connected pump.")
                                +
                                Text("This enables automated insulin delivery.").bold()
                        )
                        .foregroundColor(.secondary)
                        .font(.footnote)

                    }.padding(.vertical)
                }.listRowBackground(Color.chart)

                Section {
                    Text("Pump").navigationLink(to: .pumpConfig, from: self)
                    Text("CGM").navigationLink(to: .cgm, from: self)
                    Text("Watch").navigationLink(to: .watch, from: self)
                    // TODO: combine pump + pump settings?!
                    Text("Pump Settings").navigationLink(to: .pumpSettingsEditor, from: self)
                } header: { Text("Devices") }.listRowBackground(Color.chart)

                Section {
                    Text("Basal Profile").navigationLink(to: .basalProfileEditor, from: self)
                    Text("Insulin Sensitivities").navigationLink(to: .isfEditor, from: self)
                    Text("Carb Ratios").navigationLink(to: .crEditor, from: self)
                    Text("Target Glucose").navigationLink(to: .targetsEditor, from: self)
                    Text("Autotune").navigationLink(to: .autotuneConfig, from: self)
                } header: { Text("Profiles") }.listRowBackground(Color.chart)

                Section {
                    Text("Preferences").navigationLink(to: .preferencesEditor, from: self)
                    Text("Dynamic Settings").navigationLink(to: .dynamicISF, from: self)
                } header: { Text("Algorithm") }.listRowBackground(Color.chart)

                Section {
                    Text("UI/UX").navigationLink(to: .statisticsConfig, from: self)
                    Text("Meal Settings").navigationLink(to: .fpuConfig, from: self)
                    Text("Bolus Calculator").navigationLink(to: .bolusCalculatorConfig, from: self)
                    Text("App Icons").navigationLink(to: .iconConfig, from: self)
                } header: { Text("App Configuration") }.listRowBackground(Color.chart)

                Section {
                    Text("App Notifications").navigationLink(to: .notificationsConfig, from: self)
                    Text("Live Activity")
                } header: { Text("Notifications") }.listRowBackground(Color.chart)

                Section {
                    Text("Nightscout").navigationLink(to: .nighscoutConfig, from: self)

                    NavigationLink(destination: TidepoolStartView(state: state)) {
                        Text("Tidepool")
                    }

                    if HKHealthStore.isHealthDataAvailable() {
                        Text("Apple Health").navigationLink(to: .healthkit, from: self)
                    }

                    Text("Shortcuts", tableName: "ShortcutsDetail").navigationLink(to: .shortcutsConfig, from: self)
                } header: { Text("Services") }.listRowBackground(Color.chart)

                Section {
                    HStack {
                        Text("Share Logs")
                            .onTapGesture {
                                showShareSheet.toggle()
                            }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Submit Ticket on GitHub")
                            .onTapGesture {
                                if let url = URL(string: "https://github.com/nightscout/Trio/issues/new/choose") {
                                    UIApplication.shared.open(url)
                                }
                            }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Trio Discord")
                            .onTapGesture {
                                if let url = URL(string: "https://discord.gg/FnwFEFUwXE") {
                                    UIApplication.shared.open(url)
                                }
                            }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Trio Facebook")
                            .onTapGesture {
                                if let url = URL(string: "https://m.facebook.com/groups/1351938092206709/") {
                                    UIApplication.shared.open(url)
                                }
                            }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundColor(.secondary)
                    }
                } header: { Text("Support") }.listRowBackground(Color.chart)

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
//                            Text("Pump History")
//                                .navigationLink(to: .configEditor(file: OpenAPS.Monitor.pumpHistory), from: self)
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
//                            Text("Carbs")
//                                .navigationLink(to: .configEditor(file: OpenAPS.Monitor.carbHistory), from: self)
//                            Text("Announcements")
//                                .navigationLink(to: .configEditor(file: OpenAPS.FreeAPS.announcements), from: self)
//                            Text("Enacted announcements")
//                                .navigationLink(to: .configEditor(file: OpenAPS.FreeAPS.announcementsEnacted), from: self)
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
//                            Text("Statistics")
//                                .navigationLink(to: .configEditor(file: OpenAPS.Monitor.statistics), from: self)
                            Text("Edit settings json")
                                .navigationLink(to: .configEditor(file: OpenAPS.FreeAPS.settings), from: self)
                        }
                    }
                } header: { Text("Developer") }.listRowBackground(Color.chart)
            }.scrollContentBackground(.hidden).background(color)
                .sheet(isPresented: $showShareSheet) {
                    ShareSheet(activityItems: state.logItems())
                }
                .onAppear(perform: configureView)
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.automatic)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(
                            action: {
                                if let url = URL(string: "https://triodocs.org/") {
                                    UIApplication.shared.open(url)
                                }
                            },
                            label: {
                                HStack {
                                    Text("Trio Docs")
                                    Image(systemName: "questionmark.circle")
                                }
                            }
                        )
                    }
                }
//                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
                .onDisappear(perform: { state.uploadProfileAndSettings(false) })
                .screenNavigation(self)
        }
    }
}
