import Foundation
import Swinject

@available(iOS 16.0, *) protocol IntentsRequestType {
    var intentRequest: BaseIntentsRequest { get set }
}

@available(iOS 16.0, *) class BaseIntentsRequest: NSObject, @unchecked Sendable, Injectable {
    @Injected() var tempTargetsStorage: TempTargetsStorage!
    @Injected() var settingsManager: SettingsManager!
    @Injected() var storage: TempTargetsStorage!
    @Injected() var fileStorage: FileStorage!
    @Injected() var carbsStorage: CarbsStorage!
    @Injected() var glucoseStorage: GlucoseStorage!
    @Injected() var apsManager: APSManager!

    let resolver: Resolver

    let coredataContext = CoreDataStack.shared.persistentContainer.viewContext

    override init() {
        resolver = FreeAPSApp.resolver
        super.init()
        injectServices(resolver)
    }
}
