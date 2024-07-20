//
//  OverrideRunStored+CoreDataProperties.swift
//  FreeAPS
//
//  Created by Cengiz Deniz on 21.07.24.
//
//

import Foundation
import CoreData


extension OverrideRunStored {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<OverrideRunStored> {
        return NSFetchRequest<OverrideRunStored>(entityName: "OverrideRunStored")
    }

    @NSManaged public var endDate: Date?
    @NSManaged public var id: UUID?
    @NSManaged public var isUploadedToNS: Bool
    @NSManaged public var name: String?
    @NSManaged public var startDate: Date?
    @NSManaged public var target: NSDecimalNumber?
    @NSManaged public var override: OverrideStored?

}

extension OverrideRunStored : Identifiable {

}
