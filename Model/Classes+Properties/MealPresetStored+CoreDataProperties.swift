//
// Trio
// MealPresetStored+CoreDataProperties.swift
// Created by Deniz Cengiz on 2024-09-11.
// Last edited by Deniz Cengiz on 2024-09-11.
// Most contributions by Deniz Cengiz and Marvin Polscheit.
//
// Documentation available under: https://triodocs.org/

import CoreData
import Foundation

public extension MealPresetStored {
    @nonobjc class func fetchRequest() -> NSFetchRequest<MealPresetStored> {
        NSFetchRequest<MealPresetStored>(entityName: "MealPresetStored")
    }

    @NSManaged var carbs: NSDecimalNumber?
    @NSManaged var dish: String?
    @NSManaged var fat: NSDecimalNumber?
    @NSManaged var protein: NSDecimalNumber?
}

extension MealPresetStored: Identifiable {}
