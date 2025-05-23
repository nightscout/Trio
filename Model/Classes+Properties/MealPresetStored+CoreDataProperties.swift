// Trio
// MealPresetStored+CoreDataProperties.swift
// Created by polscm32 on 2024-07-01.

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
