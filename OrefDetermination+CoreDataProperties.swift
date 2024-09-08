//
//  OrefDetermination+CoreDataProperties.swift
//  FreeAPS
//
//  Created by Cengiz Deniz on 08.09.24.
//
//

import Foundation
import CoreData


extension OrefDetermination {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<OrefDetermination> {
        return NSFetchRequest<OrefDetermination>(entityName: "OrefDetermination")
    }

    @NSManaged public var bolus: NSDecimalNumber?
    @NSManaged public var carbRatio: NSDecimalNumber?
    @NSManaged public var carbsRequired: Int16
    @NSManaged public var cob: Int16
    @NSManaged public var currentTarget: NSDecimalNumber?
    @NSManaged public var deliverAt: Date?
    @NSManaged public var duration: NSDecimalNumber?
    @NSManaged public var enacted: Bool
    @NSManaged public var eventualBG: NSDecimalNumber?
    @NSManaged public var expectedDelta: NSDecimalNumber?
    @NSManaged public var glucose: NSDecimalNumber?
    @NSManaged public var id: UUID?
    @NSManaged public var insulinForManualBolus: NSDecimalNumber?
    @NSManaged public var insulinReq: NSDecimalNumber?
    @NSManaged public var insulinSensitivity: NSDecimalNumber?
    @NSManaged public var iob: NSDecimalNumber?
    @NSManaged public var isUploadedToNS: Bool
    @NSManaged public var manualBolusErrorString: NSDecimalNumber?
    @NSManaged public var minDelta: NSDecimalNumber?
    @NSManaged public var rate: NSDecimalNumber?
    @NSManaged public var reason: String?
    @NSManaged public var received: Bool
    @NSManaged public var reservoir: NSDecimalNumber?
    @NSManaged public var scheduledBasal: NSDecimalNumber?
    @NSManaged public var sensitivityRatio: NSDecimalNumber?
    @NSManaged public var smbToDeliver: NSDecimalNumber?
    @NSManaged public var temp: String?
    @NSManaged public var tempBasal: NSDecimalNumber?
    @NSManaged public var threshold: NSDecimalNumber?
    @NSManaged public var timestamp: Date?
    @NSManaged public var timestampEnacted: Date?
    @NSManaged public var totalDailyDose: NSDecimalNumber?
    @NSManaged public var forecasts: NSSet?

}

// MARK: Generated accessors for forecasts
extension OrefDetermination {

    @objc(addForecastsObject:)
    @NSManaged public func addToForecasts(_ value: Forecast)

    @objc(removeForecastsObject:)
    @NSManaged public func removeFromForecasts(_ value: Forecast)

    @objc(addForecasts:)
    @NSManaged public func addToForecasts(_ values: NSSet)

    @objc(removeForecasts:)
    @NSManaged public func removeFromForecasts(_ values: NSSet)

}

extension OrefDetermination : Identifiable {

}
