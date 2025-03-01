import Foundation
import HealthKit
import Swinject

final class ServiceAssembly: Assembly {
    func assemble(container: Container) {
        container.register(NotificationCenter.self) { _ in Foundation.NotificationCenter.default }
        container.register(Broadcaster.self) { _ in BaseBroadcaster() }
        container.register(GroupedIssueReporter.self) { _ in
            let reporter = CollectionIssueReporter()
            reporter.add(reporters: [
                SimpleLogReporter()
            ])
            reporter.setup()
            return reporter
        }
        container.register(CalendarManager.self) { r in BaseCalendarManager(resolver: r) }
        container.register(HKHealthStore.self) { _ in HKHealthStore() }
        container.register(HealthKitManager.self) { r in BaseHealthKitManager(resolver: r) }
        container.register(UserNotificationsManager.self) { r in BaseUserNotificationsManager(resolver: r) }
        container.register(WatchManager.self) { r in BaseWatchManager(resolver: r) }
        container.register(BolusCalculationManager.self) { r in BaseBolusCalculationManager(resolver: r) }
        container.register(GarminManager.self) { r in BaseGarminManager(resolver: r) }
        container.register(ContactImageManager.self) { r in BaseContactImageManager(resolver: r) }
        container.register(AlertPermissionsChecker.self) { r in AlertPermissionsChecker(resolver: r) }
        if #available(iOS 16.2, *) {
            container.register(LiveActivityManager.self) { r in
                LiveActivityManager(resolver: r)
            }
        }
    }
}
