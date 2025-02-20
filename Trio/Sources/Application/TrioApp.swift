import ActivityKit
import BackgroundTasks
import CoreData
import Foundation
import SwiftUI
import Swinject

@main struct TrioApp: App {
    @Environment(\.scenePhase) var scenePhase

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Read the color scheme preference from UserDefaults; defaults to system default setting
    @AppStorage("colorSchemePreference") private var colorSchemePreference: ColorSchemeOption = .systemDefault

    let coreDataStack: CoreDataStack

    @State private var appState = AppState()

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
            _ = resolver.resolve(LiveActivityBridge.self)!
        }
    }

    init() {
        debug(
            .default,
            "Trio Started: v\(Bundle.main.releaseVersionNumber ?? "")(\(Bundle.main.buildVersionNumber ?? "")) [buildDate: \(String(describing: BuildDetails.default.buildDate()))] [buildExpires: \(String(describing: BuildDetails.default.calculateExpirationDate()))]"
        )

        // Setup up the Core Data Stack
        coreDataStack = CoreDataStack.shared

        do {
            // Explicitly initialize Core Data Stacak
            try coreDataStack.initializeStack()

            // Load services
            loadServices()

            // Fix bug in iOS 18 related to the translucent tab bar
            configureTabBarAppearance()

            // Clear the persistentHistory and the NSManagedObjects that are older than 90 days every time the app starts
            cleanupOldData()
        } catch {
            debug(
                .coreData,
                "Failed to initialize Core Data Stack: \(error.localizedDescription)"
            )
            // Handle initialization failure
            fatalError("Core Data Stack initialization failed: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            Main.RootView(resolver: resolver)
                .preferredColorScheme(colorScheme(for: colorSchemePreference) ?? nil)
                .environment(\.managedObjectContext, coreDataStack.persistentContainer.viewContext)
                .environment(appState)
                .environmentObject(Icons())
                .onOpenURL(perform: handleURL)
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
            }
        }
        .backgroundTask(.appRefresh("com.trio.cleanup")) {
            await scheduleDatabaseCleaning()
            await cleanupOldData()
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

    func scheduleDatabaseCleaning() {
        let request = BGAppRefreshTaskRequest(identifier: "com.trio.cleanup")
        request.earliestBeginDate = .now.addingTimeInterval(7 * 24 * 60 * 60) // 7 days
        do {
            try BGTaskScheduler.shared.submit(request)
            debugPrint("Task scheduled successfully")
        } catch {
            debugPrint("Failed to schedule tasks")
        }
    }

    private func cleanupOldData() {
        Task {
            async let cleanupTokens: () = coreDataStack.cleanupPersistentHistoryTokens(before: Date.oneWeekAgo)
            async let purgeData: () = purgeOldNSManagedObjects()

            await cleanupTokens
            try await purgeData
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
