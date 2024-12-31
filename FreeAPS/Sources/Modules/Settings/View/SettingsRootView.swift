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
        @State private var searchText: String = ""

        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: AnyView?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false

        @Environment(\.colorScheme) var colorScheme
        @EnvironmentObject var appIcons: Icons
        @Environment(AppState.self) var appState

        private var filteredItems: [FilteredSettingItem] {
            SettingItems.filteredItems(searchText: searchText)
        }

        var body: some View {
            List {
                if searchText.isEmpty {
                    let buildDetails = BuildDetails.default

                    Section(
                        header: Text("BRANCH: \(buildDetails.branchAndSha)").textCase(nil),
                        content: {
                            let versionNumber = Bundle.main.releaseVersionNumber ?? "Unknown"
                            let buildNumber = Bundle.main.buildVersionNumber ?? "Unknown"

                            Group {
                                HStack {
                                    Image(appIcons.appIcon.rawValue)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 50, height: 50)
                                        .cornerRadius(10)
                                        .padding(.trailing, 10)
                                    VStack(alignment: .leading) {
                                        Text("Trio v\(versionNumber) (\(buildNumber))")
                                            .font(.headline)
                                        if let expirationDate = buildDetails.calculateExpirationDate() {
                                            let formattedDate = DateFormatter.localizedString(
                                                from: expirationDate,
                                                dateStyle: .medium,
                                                timeStyle: .none
                                            )
                                            Text("\(buildDetails.expirationHeaderString): \(formattedDate)")
                                                .font(.footnote)
                                                .foregroundColor(.secondary)
                                        } else {
                                            Text("Simulator Build has no expiry")
                                                .font(.footnote)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    ).listRowBackground(Color.chart)

                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.closedLoop,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = "Closed Loop"
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: "Closed Loop",
                        miniHint: "Enable automated insulin delivery.",
                        verboseHint: VStack(alignment: .leading, spacing: 10) {
                            Text(
                                "Running Trio in closed loop mode requires an active CGM sensor session and a connected pump. This enables automated insulin delivery."
                            )
                            Text(
                                "Before enabling, dial in your settings (basal / insulin sensitivity / carb ratio), and familiarize yourself with the app."
                            )
                        },
                        headerText: "Automated Insulin Delivery"
                    )

                    Section(
                        header: Text("Trio Configuration"),
                        content: {
                            ForEach(SettingItems.trioConfig) { item in
                                Text(item.title).navigationLink(to: item.view, from: self)
                            }
                        }
                    )
                    .listRowBackground(Color.chart)

                    Section(
                        header: Text("Support & Community"),
                        content: {
                            Button {
                                showShareSheet.toggle()
                            } label: {
                                HStack {
                                    Text("Share Logs")
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                        .font(.footnote)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Button {
                                if let url = URL(string: "https://github.com/nightscout/Trio/issues/new/choose") {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                HStack {
                                    Text("Submit Ticket on GitHub")
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                        .font(.footnote)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Button {
                                if let url = URL(string: "https://discord.gg/FnwFEFUwXE") {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                HStack {
                                    Text("Trio Discord")
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                        .font(.footnote)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Button {
                                if let url = URL(string: "https://m.facebook.com/groups/1351938092206709/") {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                HStack {
                                    Text("Trio Facebook")
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                        .font(.footnote)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Button {
                                if let url = URL(string: "https://diy-trio.org/") {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                HStack {
                                    Text("Trio Website")
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                        .font(.footnote)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    ).listRowBackground(Color.chart)

                } else {
                    Section(
                        header: Text("Search Results"),
                        content: {
                            ForEach(filteredItems) { filteredItem in
                                VStack(alignment: .leading) {
                                    Text(filteredItem.matchedContent).bold()
                                    if let path = filteredItem.settingItem.path {
                                        Text(path.map(\.stringValue).joined(separator: " > "))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }.navigationLink(to: filteredItem.settingItem.view, from: self)
                            }
                        }
                    ).listRowBackground(Color.chart)
                }

//                Section {
//                    Text("Targets")
//                        .navigationLink(to: .configEditor(file: OpenAPS.Settings.bgTargets), from: self)
//                    Text("Sensitivities")
//                        .navigationLink(to: .configEditor(file: OpenAPS.Settings.insulinSensitivities), from: self)
//                    Text("Profile")
//                        .navigationLink(to: .configEditor(file: OpenAPS.Settings.profile), from: self)
//                    Text("Preferences")
//                        .navigationLink(
//                            to: .configEditor(file: OpenAPS.Settings.preferences),
//                            from: self
//                        )
//                }.listRowBackground(Color.chart)

                // TODO: remove this more or less entirely; add build-time flag to enable Middleware; add settings export feature
//                Section {
//                    Toggle("Developer Options", isOn: $state.debugOptions)
//                    if state.debugOptions {
//                        Group {
//                            HStack {
//                                Text("NS Upload Profile and Settings")
//                                Button("Upload") { state.uploadProfileAndSettings(true) }
//                                    .frame(maxWidth: .infinity, alignment: .trailing)
//                                    .buttonStyle(.borderedProminent)
//                            }
//                            // Commenting this out for now, as not needed and possibly dangerous for users to be able to nuke their pump pairing informations via the debug menu
//                            // Leaving it in here, as it may be a handy functionality for further testing or developers.
//                            // See https://github.com/nightscout/Trio/pull/277 for more information
//                            //
//                            //                            HStack {
//                            //                                Text("Delete Stored Pump State Binary Files")
//                            //                                Button("Delete") { state.resetLoopDocuments() }
//                            //                                    .frame(maxWidth: .infinity, alignment: .trailing)
//                            //                                    .buttonStyle(.borderedProminent)
//                            //                            }
//                        }
//                        Group {
//                            Text("Preferences")
//                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.preferences), from: self)
//                            Text("Pump Settings")
//                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.settings), from: self)
//                            Text("Autosense")
//                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.autosense), from: self)
//                            //                            Text("Pump History")
//                            //                                .navigationLink(to: .configEditor(file: OpenAPS.Monitor.pumpHistory), from: self)
//                            Text("Basal profile")
//                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.basalProfile), from: self)
//                    Text("Targets ranges")
//                        .navigationLink(to: .configEditor(file: OpenAPS.Settings.bgTargets), from: self)
//                            Text("Temp targets")
//                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.tempTargets), from: self)
//                        }
//
//                        Group {
//                            Text("Pump profile")
//                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.pumpProfile), from: self)
//                            Text("Profile")
//                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.profile), from: self)
//                            //                            Text("Carbs")
//                            //                                .navigationLink(to: .configEditor(file: OpenAPS.Monitor.carbHistory), from: self)
//                        }
//
//                        Group {
//                            Text("Target presets")
//                                .navigationLink(to: .configEditor(file: OpenAPS.FreeAPS.tempTargetsPresets), from: self)
//                            Text("Calibrations")
//                                .navigationLink(to: .configEditor(file: OpenAPS.FreeAPS.calibrations), from: self)
//                            Text("Middleware")
//                                .navigationLink(to: .configEditor(file: OpenAPS.Middleware.determineBasal), from: self)
//                            //                            Text("Statistics")
//                            //                                .navigationLink(to: .configEditor(file: OpenAPS.Monitor.statistics), from: self)
//                            Text("Edit settings json")
//                                .navigationLink(to: .configEditor(file: OpenAPS.FreeAPS.settings), from: self)
//                        }
//                    }
//                }.listRowBackground(Color.chart)
            }
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .sheet(isPresented: $shouldDisplayHint) {
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    shouldDisplayHint: $shouldDisplayHint,
                    hintLabel: hintLabel ?? "",
                    hintText: selectedVerboseHint ?? AnyView(EmptyView()),
                    sheetTitle: "Help"
                )
            }
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
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .screenNavigation(self)
        }
    }
}
