//
// Trio
// OpenAPS_Battery+CoreDataProperties.swift
// Created by Deniz Cengiz on 2024-09-11.
// Last edited by Deniz Cengiz on 2025-01-19.
// Most contributions by Deniz Cengiz and Marvin Polscheit.
//
// Documentation available under: https://triodocs.org/

import CoreData
import Foundation

public extension OpenAPS_Battery {
    @nonobjc class func fetchRequest() -> NSFetchRequest<OpenAPS_Battery> {
        NSFetchRequest<OpenAPS_Battery>(entityName: "OpenAPS_Battery")
    }

    @NSManaged var date: Date?
    @NSManaged var display: Bool
    @NSManaged var id: UUID?
    @NSManaged var percent: Double
    @NSManaged var status: String?
    @NSManaged var voltage: NSDecimalNumber?
}

extension OpenAPS_Battery: Identifiable {}
