import CoreData
import Foundation

public extension OrefDetermination {
    @nonobjc class func fetchRequest() -> NSFetchRequest<OrefDetermination> {
        NSFetchRequest<OrefDetermination>(entityName: "OrefDetermination")
    }

    @NSManaged var bolus: NSDecimalNumber?
    @NSManaged var carbRatio: NSDecimalNumber?
    @NSManaged var carbsRequired: Int16
    @NSManaged var cob: Int16
    @NSManaged var currentTarget: NSDecimalNumber?
    @NSManaged var deliverAt: Date?
    @NSManaged var duration: NSDecimalNumber?
    @NSManaged var enacted: Bool
    @NSManaged var eventualBG: NSDecimalNumber?
    @NSManaged var expectedDelta: NSDecimalNumber?
    @NSManaged var glucose: NSDecimalNumber?
    @NSManaged var id: UUID?
    @NSManaged var insulinForManualBolus: NSDecimalNumber?
    @NSManaged var insulinReq: NSDecimalNumber?
    @NSManaged var insulinSensitivity: NSDecimalNumber?
    @NSManaged var iob: NSDecimalNumber?
    @NSManaged var isUploadedToNS: Bool
    @NSManaged var manualBolusErrorString: NSDecimalNumber?
    @NSManaged var minDelta: NSDecimalNumber?
    @NSManaged var rate: NSDecimalNumber?
    @NSManaged var reason: String?
    @NSManaged var received: Bool
    @NSManaged var reservoir: NSDecimalNumber?
    @NSManaged var scheduledBasal: NSDecimalNumber?
    @NSManaged var sensitivityRatio: NSDecimalNumber?
    @NSManaged var smbToDeliver: NSDecimalNumber?
    @NSManaged var temp: String?
    @NSManaged var tempBasal: NSDecimalNumber?
    @NSManaged var threshold: NSDecimalNumber?
    @NSManaged var timestamp: Date?
    @NSManaged var timestampEnacted: Date?
    @NSManaged var forecasts: Set<Forecast>?
}

// MARK: Generated accessors for forecasts

public extension OrefDetermination {
    @objc(addForecastsObject:)
    @NSManaged func addToForecasts(_ value: Forecast)

    @objc(removeForecastsObject:)
    @NSManaged func removeFromForecasts(_ value: Forecast)

    @objc(addForecasts:)
    @NSManaged func addToForecasts(_ values: NSSet)

    @objc(removeForecasts:)
    @NSManaged func removeFromForecasts(_ values: NSSet)
}

extension OrefDetermination: Identifiable {}
