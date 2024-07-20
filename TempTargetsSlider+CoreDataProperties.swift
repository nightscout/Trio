//
//  TempTargetsSlider+CoreDataProperties.swift
//  FreeAPS
//
//  Created by Cengiz Deniz on 21.07.24.
//
//

import Foundation
import CoreData


extension TempTargetsSlider {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<TempTargetsSlider> {
        return NSFetchRequest<TempTargetsSlider>(entityName: "TempTargetsSlider")
    }

    @NSManaged public var date: Date?
    @NSManaged public var defaultHBT: Double
    @NSManaged public var duration: NSDecimalNumber?
    @NSManaged public var enabled: Bool
    @NSManaged public var hbt: Double
    @NSManaged public var id: String?
    @NSManaged public var isPreset: Bool

}

extension TempTargetsSlider : Identifiable {

}
