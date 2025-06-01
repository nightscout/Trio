import BackgroundTasks
import CoreData
import Foundation
import SwiftUI
import Swinject

extension Notification.Name {
    static let initializationCompleted = Notification.Name("initializationCompleted")
    static let initializationError = Notification.Name("initializationError")
    static let onboardingCompleted = Notification.Name("onboardingCompleted")
}

@main struct TrioApp: App {
    @Environment(\.scenePhase) var scenePhase

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Read the color scheme preference from UserDefaults; defaults to system default setting
    @AppStorage("colorSchemePreference") private var colorSchemePreference: ColorSchemeOption = .systemDefault

    let coreDataStack = CoreDataStack.shared
    let onboardingManager = OnboardingManager.shared

    class InitState {
        var complete: Bool = false
        var error: Bool = false
        var migrationErrors: [String] = []
        var migrationFailed: Bool = false
    }

    // We use both InitState and @State variables to track coreDataStack
    // initialization. We need both to handle the cases when the coreDataStack
    // finishes before the UI and when it finishes after. SwiftUI doesn't have
    // clean mechanisms for handling background thread updates, thus this solution.
    let initState = InitState()

    @State private var appState = AppState()
    @State private var showLoadingView = true
    @State private var showLoadingError = false
    @State private var showOnboardingCompletedSplash = false
    @State private var showMigrationError: Bool = false

    // Dependencies Assembler
    // contain all dependencies Assemblies
    // TODO: Remove static key after update "Use Dependencies" logic
    private static var assembler = Assembler([
        StorageAssembly(),
        ServiceAssembly(),
        APSAssembly(),
        NetworkAssembly(),
        UIAssembly(),
        SecurityAssembly()
    ], parent: nil, defaultObjectScope: .container)

    var resolver: Resolver {
        TrioApp.assembler.resolver
    }

    // Temp static var
    // Use to backward compatibility with old Dependencies logic on Logger
    // TODO: Remove var after update "Use Dependencies" logic in Logger
    static var resolver: Resolver {
        TrioApp.assembler.resolver
    }

    private func loadServices() {
        resolver.resolve(AppearanceManager.self)!.setupGlobalAppearance()
        _ = resolver.resolve(DeviceDataManager.self)!
        _ = resolver.resolve(APSManager.self)!
        _ = resolver.resolve(FetchGlucoseManager.self)!
        _ = resolver.resolve(FetchTreatmentsManager.self)!
        _ = resolver.resolve(CalendarManager.self)!
        _ = resolver.resolve(UserNotificationsManager.self)!
        _ = resolver.resolve(WatchManager.self)!
        _ = resolver.resolve(ContactImageManager.self)!
        _ = resolver.resolve(HealthKitManager.self)!
        _ = resolver.resolve(WatchManager.self)!
        _ = resolver.resolve(GarminManager.self)!
        _ = resolver.resolve(ContactImageManager.self)!
        _ = resolver.resolve(BluetoothStateManager.self)!
        _ = resolver.resolve(PluginManager.self)!
        _ = resolver.resolve(AlertPermissionsChecker.self)!
        if #available(iOS 16.2, *) {
            _ = resolver.resolve(LiveActivityManager.self)!
        }
    }

    init() {
        FileProtectionFixer.fixFlagFileProtectionForPropertyPersistentFlags() // TODO: ‼️ REMOVE ME BEFORE PUBLIC BETA / RELEASE

        let notificationCenter = Foundation.NotificationCenter.default
        notificationCenter.addObserver(
            forName: .initializationCompleted,
            object: nil,
            queue: .main
        ) { [self] _ in
            showLoadingView = false
        }
        notificationCenter.addObserver(
            forName: .initializationError,
            object: nil,
            queue: .main
        ) { [self] _ in
            showLoadingError = true
        }
        notificationCenter.addObserver(
            forName: .onboardingCompleted,
            object: nil,
            queue: .main
        ) { [self] _ in
            showOnboardingCompletedSplash = true
        }

        let submodulesInfo = BuildDetails.shared.submodules.map { key, value in
            "\(key): \(value.branch) \(value.commitSHA)"
        }.joined(separator: ", ")

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

        debug(
            .default,
            "Trio Started: v\(devVersion)(\(Bundle.main.buildVersionNumber ?? "")) [buildDate: \(String(describing: BuildDetails.shared.buildDate()))] [buildExpires: \(String(describing: BuildDetails.shared.calculateExpirationDate()))] [Branch: \(BuildDetails.shared.branchAndSha)] [submodules: \(submodulesInfo)]"
        )
        // Fix bug in iOS 18 related to the translucent tab bar
        configureTabBarAppearance()

        deferredInitialization()
    }

    /// Handles the deferred initialization of core components.
    ///
    /// Performs CoreDataStack initialization asynchronously and notifies the UI
    /// of completion or errors via notifications.
    private func deferredInitialization() {
        Task {
            do {
                try await coreDataStack.initializeStack()

                // TODO: possibly wrap this in a UserDefault / TinyStorage flag check, so we do not even attempt to fetch files unnecessary, but early exit the import
                await performJsonToCoreDataMigrationIfNeeded()

                await Task { @MainActor in
                    // Only load services after successful Core Data initialization
                    loadServices()

                    // Clear the persistentHistory and the NSManagedObjects that are older than 90 days every time the app starts
                    cleanupOldData()

                    self.initState.complete = true

                    // Notifications handling
                    // Notify of completed initialization
                    Foundation.NotificationCenter.default.post(name: .initializationCompleted, object: nil)
                    UIApplication.shared.registerForRemoteNotifications()
                    // Cancel scheduled not looping notifications when app was completely shut down and has now re-initialized completely
                    self.clearNotLoopingNotifications()

                    do {
                        try await BuildDetails.shared.handleExpireDateChange()
                    } catch {
                        debug(.default, "Failed to handle expire date change: \(error)")
                    }
                }.value
            } catch {
                debug(
                    .coreData,
                    "\(DebuggingIdentifiers.failed) Failed to initialize Core Data Stack: \(error)"
                )

                await MainActor.run {
                    self.initState.error = true
                    Foundation.NotificationCenter.default.post(name: .initializationError, object: nil)
                }
            }
        }
    }

    @MainActor private func performJsonToCoreDataMigrationIfNeeded() async {
        let importer = JSONImporter(context: coreDataStack.newTaskContext(), coreDataStack: coreDataStack)
        var importErrors: [String] = []

        do {
            try await importer.importGlucoseHistoryIfNeeded()
        } catch {
            importErrors
                .append(String(localized: "Failed to import glucose history."))
            debug(.coreData, "❌ Failed to import JSON-based Glucose History: \(error)")
        }

        do {
            try await importer.importPumpHistoryIfNeeded()
        } catch {
            importErrors.append(String(localized: "Failed to import pump history."))
            debug(.coreData, "❌ Failed to import JSON-based Pump History: \(error)")
        }

        do {
            try await importer.importCarbHistoryIfNeeded()
        } catch {
            importErrors.append(String(localized: "Failed to import algorithm data."))
            debug(.coreData, "❌ Failed to import JSON-based Carb History: \(error)")
        }

        do {
            try await importer.importDeterminationIfNeeded()
        } catch {
            importErrors
                .append(
                    String(localized: "Migration of JSON-based OpenAPS Determination Data failed: \(error.localizedDescription)")
                )
            debug(.coreData, "❌ Failed to import JSON-based OpenAPS Determination Data: \(error)")
        }

        initState.migrationErrors = importErrors
        initState.migrationFailed = importErrors.isNotEmpty
    }

    /// Clears any legacy (Trio 0.2.x) delivered and pending notifications related to non-looping alerts.
    /// It targets the following notifications:
    /// - `noLoopFirstNotification`: The first notification for non-looping alerts.
    /// - `noLoopSecondNotification`: The second notification for non-looping alerts.
    ///
    /// It ensures that any notifications that have already been shown to the user, as well as
    /// any that are scheduled for the future, are removed when the system no longer needs to
    /// alert about non-looping conditions.
    ///
    /// This function is typically used when the app was completely shut down and restarted,
    /// i.e., underwent a fresh initialization and boot-up,  to avoid bogus not looping notifications
    /// due to dangling "zombie" pending notification requests for users that update from
    /// old Trio versions to the new generation of the app.
    ///
    /// Delivered notifications are cleared for completeness.
    private func clearNotLoopingNotifications() {
        let legacyNoLoopFirstNotification = "FreeAPS.noLoopFirstNotification"
        let legacyNoLoopSecondNotification = "FreeAPS.noLoopSecondNotification"
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [
            legacyNoLoopFirstNotification,
            legacyNoLoopSecondNotification
        ])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [
            legacyNoLoopFirstNotification,
            legacyNoLoopSecondNotification
        ])
    }

    /// Attempts to initialize the CoreDataStack again after a previous failure.
    ///
    /// Resets error states and triggers the initialization process from the beginning. Called in response
    /// to a UI "retry" button press from the Main.LoadingView
    private func retryCoreDataInitialization() {
        showLoadingError = false
        initState.error = false
        deferredInitialization()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if self.showLoadingView {
                    Main.LoadingView(showError: $showLoadingError, retry: retryCoreDataInitialization)
                        .onAppear {
                            if self.initState.complete {
                                Task { @MainActor in
                                    try? await Task.sleep(for: .seconds(1.8))
                                    self.showLoadingView = false
                                    if self.initState.migrationErrors.isNotEmpty {
                                        self.showMigrationError = true
                                    }
                                }
                            }
                            if self.initState.error {
                                self.showLoadingError = true
                            }
                        }
                        .onReceive(Foundation.NotificationCenter.default.publisher(for: .initializationCompleted)) { _ in
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(1.8))
                                self.showLoadingView = false
                                if self.initState.migrationErrors.isNotEmpty {
                                    self.showMigrationError = true
                                }
                            }
                        }
                        .onReceive(Foundation.NotificationCenter.default.publisher(for: .initializationError)) { _ in
                            self.showLoadingError = true
                        }
                } else if showMigrationError { // FIXME: display of this is not yet working, despite migration errors
                    Main.MainMigrationErrorView(migrationErrors: self.initState.migrationErrors, onConfirm: {
                        Task { @MainActor in
                            showMigrationError = false
                            initState.migrationErrors = []
                        }
                    })
                } else if showOnboardingCompletedSplash {
                    LogoBurstSplash(isActive: $showOnboardingCompletedSplash) {
                        Main.RootView(resolver: resolver)
                            .preferredColorScheme(colorScheme(for: colorSchemePreference))
                            .environment(
                                \.managedObjectContext,
                                coreDataStack.persistentContainer.viewContext
                            )
                            .environment(appState)
                            .environmentObject(Icons())
                            .onOpenURL(perform: handleURL)
                    }
                } else if onboardingManager.shouldShowOnboarding {
                    // Show onboarding if needed
                    Onboarding.RootView(
                        resolver: resolver,
                        onboardingManager: onboardingManager,
                        wasMigrationSuccessful: !initState.migrationFailed
                    )
                    .preferredColorScheme(colorScheme(for: .dark) ?? nil)
                    .transition(.opacity)
                } else {
                    Main.RootView(resolver: resolver)
                        .preferredColorScheme(colorScheme(for: colorSchemePreference) ?? nil)
                        .environment(\.managedObjectContext, coreDataStack.persistentContainer.viewContext)
                        .environment(appState)
                        .environmentObject(Icons())
                        .onOpenURL(perform: handleURL)
                }
            }
            .onReceive(Foundation.NotificationCenter.default.publisher(for: .onboardingCompleted)) { _ in
                Task { @MainActor in
                    self.showOnboardingCompletedSplash = true
                }
            }
        }
        .onChange(of: scenePhase) { _, newScenePhase in
            debug(.default, "APPLICATION PHASE: \(newScenePhase)")

            /// If the App goes to the background we should ensure that all the changes are saved from the viewContext to the Persistent Container
            if newScenePhase == .background {
                coreDataStack.save()
            }

            if newScenePhase == .active {
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
                {
                    AppVersionChecker.shared.checkAndNotifyVersionStatus(in: rootVC)
                }
                if initState.complete {
                    performCleanupIfNecessary()
                }
            }
        }
    }

    func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        appearance.backgroundColor = UIColor.clear

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    private func colorScheme(for colorScheme: ColorSchemeOption) -> ColorScheme? {
        switch colorScheme {
        case .systemDefault:
            return nil // Uses the system theme.
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    private func performCleanupIfNecessary() {
        if let lastCleanupDate = PropertyPersistentFlags.shared.lastCleanupDate {
            let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
            if lastCleanupDate < sevenDaysAgo {
                cleanupOldData()
            }
        }
    }

    private func cleanupOldData() {
        Task {
            async let cleanupTokens: () = coreDataStack.cleanupPersistentHistoryTokens(before: Date.oneWeekAgo)
            async let purgeData: () = purgeOldNSManagedObjects()

            await cleanupTokens
            try await purgeData

            // Update the last cleanup date
            PropertyPersistentFlags.shared.lastCleanupDate = Date()
        }
    }

    private func purgeOldNSManagedObjects() async throws {
        async let glucoseDeletion: () = coreDataStack.batchDeleteOlderThan(GlucoseStored.self, dateKey: "date", days: 90)
        async let pumpEventDeletion: () = coreDataStack.batchDeleteOlderThan(PumpEventStored.self, dateKey: "timestamp", days: 90)
        async let bolusDeletion: () = coreDataStack.batchDeleteOlderThan(
            parentType: PumpEventStored.self,
            childType: BolusStored.self,
            dateKey: "timestamp",
            days: 90,
            relationshipKey: "pumpEvent"
        )
        async let tempBasalDeletion: () = coreDataStack.batchDeleteOlderThan(
            parentType: PumpEventStored.self,
            childType: TempBasalStored.self,
            dateKey: "timestamp",
            days: 90,
            relationshipKey: "pumpEvent"
        )
        async let determinationDeletion: () = coreDataStack
            .batchDeleteOlderThan(OrefDetermination.self, dateKey: "deliverAt", days: 90)
        async let batteryDeletion: () = coreDataStack.batchDeleteOlderThan(OpenAPS_Battery.self, dateKey: "date", days: 90)
        async let carbEntryDeletion: () = coreDataStack.batchDeleteOlderThan(CarbEntryStored.self, dateKey: "date", days: 90)
        async let forecastDeletion: () = coreDataStack.batchDeleteOlderThan(Forecast.self, dateKey: "date", days: 2)
        async let forecastValueDeletion: () = coreDataStack.batchDeleteOlderThan(
            parentType: Forecast.self,
            childType: ForecastValue.self,
            dateKey: "date",
            days: 2,
            relationshipKey: "forecast"
        )
        async let overrideDeletion: () = coreDataStack
            .batchDeleteOlderThan(OverrideStored.self, dateKey: "date", days: 3, isPresetKey: "isPreset")
        async let overrideRunDeletion: () = coreDataStack
            .batchDeleteOlderThan(OverrideRunStored.self, dateKey: "startDate", days: 3)

        // Await each task to ensure they are all completed
        try await glucoseDeletion
        try await pumpEventDeletion
        try await bolusDeletion
        try await tempBasalDeletion
        try await determinationDeletion
        try await batteryDeletion
        try await carbEntryDeletion
        try await forecastDeletion
        try await forecastValueDeletion
        try await overrideDeletion
        try await overrideRunDeletion
    }

    private func handleURL(_ url: URL) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        switch components?.host {
        case "device-select-resp":
            resolver.resolve(NotificationCenter.self)!.post(name: .openFromGarminConnect, object: url)
        default: break
        }
    }
}

public extension Bundle {
    var appDevVersion: String? {
        object(forInfoDictionaryKey: "AppDevVersion") as? String
    }
}
