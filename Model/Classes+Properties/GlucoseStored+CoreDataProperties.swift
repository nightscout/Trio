//
// Trio
// GlucoseStored+CoreDataProperties.swift
// Created by Deniz Cengiz on 2024-09-11.
// Last edited by Deniz Cengiz on 2024-09-15.
// Most contributions by Deniz Cengiz and Marvin Polscheit.
//
// Documentation available under: https://triodocs.org/

import CoreData
import Foundation

public extension GlucoseStored {
    @nonobjc class func fetchRequest() -> NSFetchRequest<GlucoseStored> {
        NSFetchRequest<GlucoseStored>(entityName: "GlucoseStored")
    }

    @NSManaged var date: Date?
    @NSManaged var direction: String?
    @NSManaged var glucose: Int16
    @NSManaged var id: UUID?
    @NSManaged var isManual: Bool
    @NSManaged var isUploadedToNS: Bool
    @NSManaged var isUploadedToHealth: Bool
    @NSManaged var isUploadedToTidepool: Bool
}

extension GlucoseStored: Identifiable {}
