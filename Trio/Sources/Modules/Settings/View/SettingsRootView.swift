import HealthKit
import LoopKit
import LoopKitUI
import SwiftUI
import Swinject

extension Settings {
    struct VersionInfo: Equatable {
        var latestVersion: String?
        var isUpdateAvailable: Bool
        var isBlacklisted: Bool
    }

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
        @State private var versionInfo = VersionInfo(
            latestVersion: nil,
            isUpdateAvailable: false,
            isBlacklisted: false
        )
        @State private var closedLoopDisabled = true

        @Environment(\.colorScheme) var colorScheme
        @EnvironmentObject var appIcons: Icons
        @Environment(AppState.self) var appState

        private var filteredItems: [FilteredSettingItem] {
            SettingItems.filteredItems(searchText: searchText)
        }

        @ViewBuilder var versionInfoView: some View {
            let latestVersion = versionInfo.latestVersion
            if let version = latestVersion {
                let updateColor: Color = versionInfo.isUpdateAvailable ? .orange : .green
                let versionIconName = versionInfo.isUpdateAvailable ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Latest version: \(version)")
                            .font(.footnote)
                            .foregroundColor(updateColor)
                        Image(systemName: versionIconName)
                            .foregroundColor(updateColor)
                    }
                    if versionInfo.isBlacklisted {
                        HStack {
                            Text("Warning: Known issues. Update now.")
                                .font(.footnote)
                                .foregroundColor(.red)
                            Image(systemName: "exclamationmark.octagon.fill")
                                .foregroundColor(.red)
                        }
                    }
                }
            } else {
                Text("Latest version: Fetching...")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }

        var body: some View {
            List {
                if searchText.isEmpty {
                    let buildDetails = BuildDetails.shared

                    Section(
                        header: Text("BRANCH: \(buildDetails.branchAndSha)").textCase(nil),
                        content: {
                            /// The current development version of the app.
                            ///
                            /// Follows a semantic pattern where release versions are like `0.5.0`, and
                            /// development versions increment with a fourth component (e.g., `0.5.0.1`, `0.5.0.2`)
                            /// after the base release. For example:
                            /// - After release `0.5.0` → `0.5.0`
                            /// - First dev push → `0.5.0.1`
                            /// - Next dev push → `0.5.0.2`
                            /// - Next release `0.6.0` → `0.6.0`
                            /// - Next dev push → `0.6.0.1`
                            ///
                            /// If the dev version is unavailable, `"unknown"` is returned.
                            let devVersion = Bundle.main.appDevVersion ?? "unknown"

                            let buildNumber = Bundle.main.buildVersionNumber ?? String(localized: "Unknown")

                            NavigationLink(destination: SubmodulesView(buildDetails: buildDetails)) {
                                HStack {
                                    Image(appIcons.appIcon.rawValue)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 50, height: 50)
                                        .cornerRadius(10)
                                        .padding(.trailing, 10)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Trio v\(devVersion) (\(buildNumber))")
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

                                        versionInfoView
                                    }
                                }
                            }
                        }
                    ).listRowBackground(Color.chart)

                    let miniHintText = closedLoopDisabled ?
                        String(localized: "Add a CGM and pump to enable automated insulin delivery") :
                        String(localized: "Enable automated insulin delivery.")
                    let miniHintTextColorForDisabled: Color = colorScheme == .dark ? .orange : .accentColor
                    let miniHintTextColor: Color = closedLoopDisabled ? miniHintTextColorForDisabled : .secondary
                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.closedLoop,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = String(localized: "Closed Loop")
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: String(localized: "Closed Loop"),
                        miniHint: miniHintText,
                        verboseHint: VStack(alignment: .leading, spacing: 10) {
                            Text(
                                "Running Trio in closed loop mode requires an active CGM sensor session and a connected pump. This enables automated insulin delivery."
                            )
                            Text(
                                "Before enabling, dial in your settings (basal / insulin sensitivity / carb ratio), and familiarize yourself with the app."
                            )
                        },
                        headerText: String(localized: "Automated Insulin Delivery"),
                        isToggleDisabled: closedLoopDisabled,
                        miniHintColor: miniHintTextColor
                    )
                    .onAppear {
                        closedLoopDisabled = !state.hasCgmAndPump()
                    }

                    Section(
                        header: Text("Trio Configuration"),
                        content: {
                            ForEach(SettingItems.trioConfig) { item in
                                Text(LocalizedStringKey(item.title)).navigationLink(to: item.view, from: self)
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
                                if let url = URL(string: "https://discord.triodocs.org") {
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
                                if let url = URL(string: "https://facebook.triodocs.org") {
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
                        }
                    ).listRowBackground(Color.chart)

                } else {
                    Section(
                        header: Text("Search Results"),
                        content: {
                            if filteredItems.isNotEmpty {
                                ForEach(filteredItems) { filteredItem in
                                    VStack(alignment: .leading) {
                                        Text(filteredItem.matchedContent.localized).bold()
                                        if let path = filteredItem.settingItem.path {
                                            Text(path.map(\.localized).joined(separator: " > "))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }

                                    }.navigationLink(to: filteredItem.settingItem.view, from: self)
                                }
                            } else {
                                Text("No settings matching your search query")
                                    +
                                    Text(" »\(searchText)« ").bold()
                                    +
                                    Text("found.")
                            }
                        }
                    ).listRowBackground(Color.chart)
                }

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
//                                .navigationLink(to: .configEditor(file: OpenAPS.Trio.tempTargetsPresets), from: self)
//                            Text("Calibrations")
//                                .navigationLink(to: .configEditor(file: OpenAPS.Trio.calibrations), from: self)
//                            Text("Middleware")
//                                .navigationLink(to: .configEditor(file: OpenAPS.Middleware.determineBasal), from: self)
//                            //                            Text("Statistics")
//                            //                                .navigationLink(to: .configEditor(file: OpenAPS.Monitor.statistics), from: self)
//                            Text("Edit settings json")
//                                .navigationLink(to: .configEditor(file: OpenAPS.Trio.settings), from: self)
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
                    sheetTitle: String(localized: "Help", comment: "Help sheet title")
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
            .onAppear {
                AppVersionChecker.shared.refreshVersionInfo { _, latestVersion, isNewer, isBlacklisted in
                    let updateAvailable = isNewer
                    DispatchQueue.main.async {
                        versionInfo = VersionInfo(
                            latestVersion: latestVersion,
                            isUpdateAvailable: updateAvailable,
                            isBlacklisted: isBlacklisted
                        )
                    }
                }
            }
        }
    }
}
