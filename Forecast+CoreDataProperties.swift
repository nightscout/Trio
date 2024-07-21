//
//  Forecast+CoreDataProperties.swift
//  FreeAPS
//
//  Created by Cengiz Deniz on 21.07.24.
//
//

import Foundation
import CoreData


extension Forecast {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Forecast> {
        return NSFetchRequest<Forecast>(entityName: "Forecast")
    }

    @NSManaged public var date: Date?
    @NSManaged public var id: UUID?
    @NSManaged public var type: String?
    @NSManaged public var forecastValues: Set<ForecastValue>?
    @NSManaged public var orefDetermination: OrefDetermination?

}

// MARK: Generated accessors for forecastValues
extension Forecast {

    @objc(addForecastValuesObject:)
    @NSManaged public func addToForecastValues(_ value: ForecastValue)

    @objc(removeForecastValuesObject:)
    @NSManaged public func removeFromForecastValues(_ value: ForecastValue)

    @objc(addForecastValues:)
    @NSManaged public func addToForecastValues(_ values: NSSet)

    @objc(removeForecastValues:)
    @NSManaged public func removeFromForecastValues(_ values: NSSet)

}

extension Forecast : Identifiable {

}
