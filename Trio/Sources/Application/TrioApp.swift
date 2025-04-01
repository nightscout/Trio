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
        var complete = false
        var error = false
    }

    // We use both InitState and @State variables to track coreDataStack
    // initialization. We need both to handle the cases when the coreDataStack
    // finishes before the UI and when it finishes after. SwiftUI doesn't have
    // clean mechanisms for handling background thread updates, thus this solution.
    let initState = InitState()

    @State private var appState = AppState()
    @State private var showLoadingView = true
    @State private var showLoadingError = false
    @State private var showOnboardingView = false

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
            showOnboardingView = false
        }

        let submodulesInfo = BuildDetails.shared.submodules.map { key, value in
            "\(key): \(value.branch) \(value.commitSHA)"
        }.joined(separator: ", ")

        debug(
            .default,
            "Trio Started: v\(Bundle.main.releaseVersionNumber ?? "")(\(Bundle.main.buildVersionNumber ?? "")) [buildDate: \(String(describing: BuildDetails.shared.buildDate()))] [buildExpires: \(String(describing: BuildDetails.shared.calculateExpirationDate()))] [submodules: \(submodulesInfo)]"
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

                await Task { @MainActor in
                    // Only load services after successful Core Data initialization
                    loadServices()

                    // Clear the persistentHistory and the NSManagedObjects that are older than 90 days every time the app starts
                    cleanupOldData()

                    self.initState.complete = true
                    Foundation.NotificationCenter.default.post(name: .initializationCompleted, object: nil)
                    UIApplication.shared.registerForRemoteNotifications()
                    do {
                        try await BuildDetails.shared.handleExpireDateChange()
                    } catch {
                        debug(.default, "Failed to handle expire date change: \(error)")
                    }
                }.value
            } catch {
                debug(
                    .coreData,
                    "\(DebuggingIdentifiers.failed) Failed to initialize Core Data Stack: \(error.localizedDescription)"
                )

                await MainActor.run {
                    self.initState.error = true
                    Foundation.NotificationCenter.default.post(name: .initializationError, object: nil)
                }
            }
        }
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
            if self.showLoadingView {
                Main.LoadingView(showError: $showLoadingError, retry: retryCoreDataInitialization)
                    .onAppear {
                        if self.initState.complete {
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(1.8))
                                self.showLoadingView = false
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
                        }
                    }
                    .onReceive(Foundation.NotificationCenter.default.publisher(for: .initializationError)) { _ in
                        self.showLoadingError = true
                    }
            } else if onboardingManager.shouldShowOnboarding {
                // Show onboarding if needed
                Onboarding.RootView(resolver: resolver, onboardingManager: onboardingManager)
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
        if let lastCleanupDate = UserDefaults.standard.object(forKey: "lastCleanupDate") as? Date {
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
            UserDefaults.standard.set(Date(), forKey: "lastCleanupDate")
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
