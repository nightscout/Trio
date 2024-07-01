import ActivityKit
import BackgroundTasks
import CoreData
import Foundation
import SwiftUI
import Swinject

@main struct FreeAPSApp: App {
    @Environment(\.scenePhase) var scenePhase

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    let coreDataStack = CoreDataStack.shared

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
        FreeAPSApp.assembler.resolver
    }

    // Temp static var
    // Use to backward compatibility with old Dependencies logic on Logger
    // TODO: Remove var after update "Use Dependencies" logic in Logger
    static var resolver: Resolver {
        FreeAPSApp.assembler.resolver
    }

    private func loadServices() {
        resolver.resolve(AppearanceManager.self)!.setupGlobalAppearance()
        _ = resolver.resolve(DeviceDataManager.self)!
        _ = resolver.resolve(APSManager.self)!
        _ = resolver.resolve(FetchGlucoseManager.self)!
        _ = resolver.resolve(FetchTreatmentsManager.self)!
        _ = resolver.resolve(FetchAnnouncementsManager.self)!
        _ = resolver.resolve(CalendarManager.self)!
        _ = resolver.resolve(UserNotificationsManager.self)!
        _ = resolver.resolve(WatchManager.self)!
        _ = resolver.resolve(HealthKitManager.self)!
        _ = resolver.resolve(BluetoothStateManager.self)!
        if #available(iOS 16.2, *) {
            _ = resolver.resolve(LiveActivityBridge.self)!
        }
    }

    init() {
        debug(
            .default,
            "iAPS Started: v\(Bundle.main.releaseVersionNumber ?? "")(\(Bundle.main.buildVersionNumber ?? "")) [buildDate: \(Bundle.main.buildDate)] [buildExpires: \(Bundle.main.profileExpiration)]"
        )
        loadServices()

        // Clear the persistentHistory and the NSManagedObjects that are older than 90 days every time the app starts
        cleanupOldData()
    }

    var body: some Scene {
        WindowGroup {
            Main.RootView(resolver: resolver)
                .environment(\.managedObjectContext, coreDataStack.persistentContainer.viewContext)
                .environmentObject(Icons())
                .onOpenURL(perform: handleURL)
        }
        .onChange(of: scenePhase) { newScenePhase in
            debug(.default, "APPLICATION PHASE: \(newScenePhase)")

            /// If the App goes to the background we should ensure that all the changes are saved from the viewContext to the Persistent Container
            if newScenePhase == .background {
                coreDataStack.save()
            }
        }
        .backgroundTask(.appRefresh("com.openiaps.cleanup")) {
            await scheduleDatabaseCleaning()
            await cleanupOldData()
        }
    }

    func scheduleDatabaseCleaning() {
        let request = BGAppRefreshTaskRequest(identifier: "com.openiaps.cleanup")
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
            await coreDataStack.cleanupPersistentHistoryTokens(before: Date.oneWeekAgo)
            try await purgeOldNSManagedObjects()
        }
    }

    private func purgeOldNSManagedObjects() async throws {
        try await coreDataStack.batchDeleteOlderThan(GlucoseStored.self, dateKey: "date", days: 90)
        try await coreDataStack.batchDeleteOlderThan(PumpEventStored.self, dateKey: "timestamp", days: 90)
        try await coreDataStack.batchDeleteOlderThan(
            parentType: PumpEventStored.self,
            childType: BolusStored.self,
            dateKey: "timestamp",
            days: 90,
            relationshipKey: "pumpEvent"
        )
        try await coreDataStack.batchDeleteOlderThan(
            parentType: PumpEventStored.self,
            childType: TempBasalStored.self,
            dateKey: "timestamp",
            days: 90,
            relationshipKey: "pumpEvent"
        )
        try await coreDataStack.batchDeleteOlderThan(OrefDetermination.self, dateKey: "deliverAt", days: 90)
        try await coreDataStack.batchDeleteOlderThan(OpenAPS_Battery.self, dateKey: "date", days: 90)
        try await coreDataStack.batchDeleteOlderThan(CarbEntryStored.self, dateKey: "date", days: 90)
        try await coreDataStack.batchDeleteOlderThan(Forecast.self, dateKey: "date", days: 2)
        try await coreDataStack.batchDeleteOlderThan(
            parentType: Forecast.self,
            childType: ForecastValue.self,
            dateKey: "date",
            days: 2,
            relationshipKey: "forecast"
        )
        try await coreDataStack.batchDeleteOlderThan(OverrideStored.self, dateKey: "date", days: 3)
        try await coreDataStack.batchDeleteOlderThan(OverrideRunStored.self, dateKey: "startDate", days: 3)

        // TODO: - Purge Data of other (future) entities as well
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
