//
// Trio
// StatsData+CoreDataProperties.swift
// Created by Deniz Cengiz on 2024-09-11.
// Last edited by Deniz Cengiz on 2024-09-11.
// Most contributions by Deniz Cengiz and Marvin Polscheit.
//
// Documentation available under: https://triodocs.org/

import CoreData
import Foundation

public extension StatsData {
    @nonobjc class func fetchRequest() -> NSFetchRequest<StatsData> {
        NSFetchRequest<StatsData>(entityName: "StatsData")
    }

    @NSManaged var lastrun: Date?
}

extension StatsData: Identifiable {}
