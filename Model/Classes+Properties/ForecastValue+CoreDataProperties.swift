// Trio
// ForecastValue+CoreDataProperties.swift
// Created by dnzxy on 2024-04-21.

import CoreData
import Foundation

public extension ForecastValue {
    @nonobjc class func fetchRequest() -> NSFetchRequest<ForecastValue> {
        NSFetchRequest<ForecastValue>(entityName: "ForecastValue")
    }

    @NSManaged var index: Int32
    @NSManaged var value: Int32
    @NSManaged var forecast: Forecast?
}

extension ForecastValue: Identifiable {}
