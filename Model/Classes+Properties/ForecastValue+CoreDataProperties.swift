//
// Trio
// ForecastValue+CoreDataProperties.swift
// Created by Deniz Cengiz on 2024-09-11.
// Last edited by Deniz Cengiz on 2024-09-11.
// Most contributions by Deniz Cengiz and dnzxy.
//
// Documentation available under: https://triodocs.org/

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
