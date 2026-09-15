import HealthKit
import LoopKit
import LoopKitUI
import SwiftUI
import Swinject
import UIKit

extension Settings {
    struct VersionInfo: Equatable {
        var latestVersion: String?
        var isUpdateAvailable: Bool
        var isBlacklisted: Bool
        var latestDevVersion: String?
        var isDevUpdateAvailable: Bool
    }

    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @State private var showShareSheet = false
        @State private var searchText: String = ""
        @State var hintDetent = PresentationDetent.large
        @State private var hintPayload: HintPayload?

        private struct HintPayload: Identifiable {
            let id = UUID()
            let label: String
            let content: AnyView
        }

        private var shouldDisplayHintBinding: Binding<Bool> {
            Binding(
                get: { hintPayload != nil },
                set: { newValue in
                    if !newValue {
                        hintPayload = nil
                    } else if hintPayload == nil {
                        hintPayload = HintPayload(label: "", content: AnyView(EmptyView()))
                    }
                }
            )
        }

        @State private var versionInfo = VersionInfo(
            latestVersion: nil,
            isUpdateAvailable: false,
            isBlacklisted: false,
            latestDevVersion: nil,
            isDevUpdateAvailable: false
        )
        @State private var dosingModeDisabled = true
        @State private var showCopiedToast = false
        @ObservedObject private var releaseNotesService = ReleaseNotesService.shared

        // MARK: - Mock chart data (development aid; see `MockChartDataSeeder`)

        /// Whether seeded records are currently in the store. Read from the store on appear
        /// rather than remembered in `UserDefaults`, so the switch tells the truth even after
        /// a reinstall, a restore, or a purge from somewhere else.
        @State private var mockDataPresent = false
        @State private var mockDataBusy = false
        @State private var mockDataStatus: String?

        @Environment(\.colorScheme) var colorScheme
        @EnvironmentObject var appIcons: Icons
        @Environment(AppState.self) var appState
        @Environment(SettingsSearchHighlight.self) var searchHighlight

        private var filteredItems: [FilteredSettingItem] {
            SettingItems.filteredItems(searchText: searchText)
        }

        @ViewBuilder var versionInfoView: some View {
            VStack(alignment: .leading, spacing: 4) {
                // Main version info
                if let version = versionInfo.latestVersion {
                    let updateColor: Color = versionInfo.isUpdateAvailable ? .orange : .green
                    let versionIconName = versionInfo
                        .isUpdateAvailable ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"

                    HStack {
                        Text("Latest version: \(version)")
                            .font(.footnote)
                            .foregroundColor(updateColor)
                        Image(systemName: versionIconName)
                            .foregroundColor(updateColor)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Latest version: \(version), " + (
                        versionInfo.isUpdateAvailable
                            ? String(localized: "update available", comment: "Accessibility: version status")
                            : String(localized: "up to date", comment: "Accessibility: version status")
                    )))
                    if versionInfo.isBlacklisted {
                        HStack {
                            Text("Warning: Known issues. Update now.")
                                .font(.footnote)
                                .foregroundColor(.red)
                            Image(systemName: "exclamationmark.octagon.fill")
                                .foregroundColor(.red)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } else {
                    Text("Latest version: Fetching...")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                // Show latest dev version on any branch except main
                let buildDetails = BuildDetails.shared
                if buildDetails.trioBranch != "main" {
                    if let devVersion = versionInfo.latestDevVersion {
                        let devUpdateColor: Color = versionInfo.isDevUpdateAvailable ? .orange : .secondary
                        let devVersionIconName = versionInfo.isDevUpdateAvailable ? "arrow.up.circle.fill" : "hammer.fill"

                        HStack {
                            Text("Latest dev: \(devVersion)")
                                .font(.footnote)
                                .foregroundColor(devUpdateColor)
                            Image(systemName: devVersionIconName)
                                .font(.footnote)
                                .foregroundColor(devUpdateColor)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("Latest dev: \(devVersion), " + (
                            versionInfo.isDevUpdateAvailable
                                ? String(localized: "update available", comment: "Accessibility: version status")
                                : String(localized: "up to date", comment: "Accessibility: version status")
                        )))
                    } else {
                        Text("Latest dev: Fetching...")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }

        // MARK: - Mock chart data

        /// Development aid: fills the chart's 72 h history with generated readings and
        /// treatments, and takes them out again. Everything it writes is marked, so turning
        /// the switch back off removes exactly what it added and nothing else.
        ///
        /// Deliberately unlocalized — this section is a testing tool, not product surface.
        @ViewBuilder private var mockChartDataSection: some View {
            Section(
                header: Text(verbatim: "Developer"),
                footer: Text(
                    verbatim: """
                    Writes generated CGM readings, boluses, SMBs, carbs and FPUs into the last 72 hours. \
                    Each day gets two deliberately crowded stretches: one SMB on every reading from 13:00, \
                    and a labelled bolus every minute from 09:00. They run 1 h, 2 h and 3 h — one length \
                    per day, so a full seed holds one of each.

                    Trio cannot tell these apart from real data: the loop will treat them as your glucose \
                    history and dose on them. Only switch this on with no pump connected.
                    """
                ),
                content: {
                    Toggle(isOn: mockDataBinding) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: "72 h of mock chart data")
                            if let mockDataStatus {
                                Text(verbatim: mockDataStatus)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .disabled(mockDataBusy)

                    // Seeding is anchored to absolute time, so a later run adds only the hours
                    // that have passed since — and anything a partial failure left missing.
                    if mockDataPresent {
                        Button {
                            Task { await seedMockData() }
                        } label: {
                            HStack {
                                Text(verbatim: "Fill in gaps since last run")
                                    .foregroundColor(.primary)
                                Spacer()
                                if mockDataBusy {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(mockDataBusy)
                    }
                }
            ).listRowBackground(Color.chart)
        }

        private var mockDataBinding: Binding<Bool> {
            Binding(
                get: { mockDataPresent },
                set: { wantsData in
                    guard !mockDataBusy else { return }
                    // Move the switch now and correct it if the work fails: seeding 72 h takes
                    // long enough that leaving it sitting in its old position reads as a
                    // control that did not respond.
                    mockDataPresent = wantsData
                    Task {
                        if wantsData {
                            await seedMockData()
                        } else {
                            await purgeMockData()
                        }
                    }
                }
            )
        }

        @MainActor private func seedMockData() async {
            mockDataBusy = true
            mockDataStatus = "Generating…"
            defer { mockDataBusy = false }
            do {
                let summary = try await MockChartDataSeeder.seed()
                mockDataPresent = true
                mockDataStatus = summary.total == 0
                    ? "Already complete — nothing to fill in"
                    : "Added \(summary.glucose) readings, \(summary.boluses) boluses, "
                    + "\(summary.smbs) SMBs, \(summary.carbs) carb entries, \(summary.fpus) FPUs"
            } catch {
                // Whatever was written before the failure is still marked, so the switch stays
                // on and the purge can still reach it.
                mockDataPresent = ((try? await MockChartDataSeeder.seededRecordCount()) ?? 0) > 0
                mockDataStatus = "Failed: \(error.localizedDescription)"
            }
        }

        @MainActor private func purgeMockData() async {
            mockDataBusy = true
            mockDataStatus = "Removing…"
            defer { mockDataBusy = false }
            do {
                let deleted = try await MockChartDataSeeder.purge()
                mockDataPresent = false
                mockDataStatus = "Removed \(deleted) records"
            } catch {
                mockDataPresent = true
                mockDataStatus = "Failed: \(error.localizedDescription)"
            }
        }

        @MainActor private func refreshMockDataState() async {
            guard !mockDataBusy else { return }
            let count = (try? await MockChartDataSeeder.seededRecordCount()) ?? 0
            mockDataPresent = count > 0
            mockDataStatus = count > 0 ? "\(count) seeded records in the store" : nil
        }

        private func copyVersionInfo(_ text: String) {
            UIPasteboard.general.string = text
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation { showCopiedToast = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation { showCopiedToast = false }
            }
        }

        var body: some View {
            List {
                if searchText.isEmpty {
                    let buildDetails = BuildDetails.shared

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

                    Section(
                        header: HStack(spacing: 4) {
                            Button {
                                copyVersionInfo(
                                    "Trio v\(devVersion) (\(buildNumber)) \(buildDetails.branchAndSha)"
                                )
                            } label: {
                                Image(systemName: "doc.on.doc.fill")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Copy version information"))
                            Text("BRANCH: \(buildDetails.branchAndSha)")
                        }.textCase(nil),
                        content: {
                            NavigationLink(destination: SubmodulesView(buildDetails: buildDetails)) {
                                HStack {
                                    Image(appIcons.appIcon.rawValue)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 50, height: 50)
                                        .cornerRadius(10)
                                        .padding(.trailing, 10)
                                        .accessibilityHidden(true)
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

                    let miniHintTextColorForDisabled: Color = colorScheme == .dark ? .orange : .accentColor
                    let miniHintTextColor: Color = dosingModeDisabled ? miniHintTextColorForDisabled : .secondary
                    Section(
                        header: Text("Automated Insulin Delivery"),
                        content: {
                            VStack {
                                Picker(
                                    selection: $state.dosingMode,
                                    label: Text("Dosing Mode")
                                ) {
                                    ForEach(DosingMode.userSelectable) { mode in
                                        Text(mode.displayName).tag(mode)
                                    }
                                }
                                .padding(.top)
                                .disabled(dosingModeDisabled)

                                HStack(alignment: .center) {
                                    Text(
                                        dosingModeDisabled ?
                                            String(localized: "Add a CGM and pump to enable automated insulin delivery") :
                                            state.dosingMode.miniHint
                                    )
                                    .font(.footnote)
                                    .foregroundColor(miniHintTextColor)
                                    .lineLimit(nil)
                                    Spacer()
                                    Button(
                                        action: {
                                            hintPayload = HintPayload(
                                                label: String(localized: "Dosing Mode"),
                                                content: AnyView(
                                                    VStack(alignment: .leading, spacing: 10) {
                                                        Text(
                                                            "Dosing Mode decides how much of Trio's insulin dosing decision is actually sent to your pump. Every mode still needs an active CGM sensor session and a connected pump."
                                                        )
                                                        ForEach(DosingMode.userSelectable) { mode in
                                                            VStack(alignment: .leading, spacing: 5) {
                                                                Label(mode.displayName, systemImage: mode.icon)
                                                                    .bold()
                                                                Text(mode.description)
                                                            }
                                                        }
                                                    }
                                                )
                                            )
                                        },
                                        label: {
                                            HStack {
                                                Image(systemName: "questionmark.circle")
                                            }
                                        }
                                    ).buttonStyle(BorderlessButtonStyle())
                                }.padding(.top)
                            }.padding(.bottom)
                        }
                    )
                    .listRowBackground(Color.chart)
                    .settingsSearchTarget(label: String(localized: "Dosing Mode"))
                    .onAppear {
                        dosingModeDisabled = !state.hasCgmAndPump()
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

                    if !releaseNotesService.releases.isEmpty {
                        Section(
                            header: Text("Release Notes"),
                            content: {
                                if let current = releaseNotesService.notes {
                                    NavigationLink(destination: ReleaseNotesDetailView(notes: current)) {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(current.name)
                                                    .foregroundColor(.primary)

                                                Text(
                                                    "Current release",
                                                    comment: "Marks the release notes entry matching the running build"
                                                )
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            }

                                            Spacer()

                                            Text(current.publishedDateString)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }

                                if !releaseNotesService.previousReleases.isEmpty {
                                    NavigationLink(
                                        destination: ReleaseNotesListView(releases: releaseNotesService.previousReleases)
                                    ) {
                                        Text("Previous Versions")
                                            .foregroundColor(.primary)
                                    }
                                }
                            }
                        ).listRowBackground(Color.chart)
                    }

                    Section(
                        header: Text("Trio Backup"),
                        content: {
                            Text(String(
                                localized: "Export Settings",
                                comment: "Export Settings menu item in Trio Settings Root View"
                            ))
                                .navigationLink(to: .settingsExport, from: self)
                        }
                    ).listRowBackground(Color.chart)

                    mockChartDataSection

                } else {
                    Section(
                        header: Text("Search Results"),
                        content: {
                            if filteredItems.isNotEmpty {
                                ForEach(filteredItems) { filteredItem in
                                    NavigationLink(value: SearchResultTarget(
                                        screen: filteredItem.settingItem.view,
                                        scrollLabel: filteredItem.scrollLabel.localized
                                    )) {
                                        VStack(alignment: .leading) {
                                            Text(filteredItem.matchedContent.localized).bold()
                                            if let path = filteredItem.settingItem.path {
                                                Text(path.map(\.localized).joined(separator: " > "))
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
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
            }
            .overlay(alignment: .bottom) {
                if showCopiedToast {
                    Label("Copied", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 32)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .sheet(item: $hintPayload) { payload in
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    shouldDisplayHint: shouldDisplayHintBinding,
                    hintLabel: payload.label,
                    hintText: payload.content,
                    sheetTitle: String(localized: "Help", comment: "Help sheet title")
                )
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(activityItems: state.logItems())
            }
            .onAppear(perform: configureView)
            .task {
                await releaseNotesService.load()
            }
            .task {
                await refreshMockDataState()
            }
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
            .navigationDestination(for: SearchResultTarget.self) { target in
                state.view(for: target.screen)
                    .onAppear {
                        searchHighlight.highlightedSetting = target.scrollLabel
                    }
            }
            .screenNavigation(self)
            .onAppear {
                Task { @MainActor in
                    let (_, latestVersion, isNewer, isBlacklisted) = await AppVersionChecker.shared.refreshVersionInfo()
                    versionInfo.latestVersion = latestVersion
                    versionInfo.isUpdateAvailable = isNewer
                    versionInfo.isBlacklisted = isBlacklisted

                    // Fetch dev version if not on main branch
                    let buildDetails = BuildDetails.shared
                    if buildDetails.trioBranch != "main" {
                        let (devVersion, isDevNewer) = await AppVersionChecker.shared.checkForNewDevVersion()
                        versionInfo.latestDevVersion = devVersion
                        versionInfo.isDevUpdateAvailable = isDevNewer
                    }
                }
            }
        }
    }
}
