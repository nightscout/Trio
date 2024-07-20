//
//  OpenAPS_Battery+CoreDataProperties.swift
//  FreeAPS
//
//  Created by Cengiz Deniz on 21.07.24.
//
//

import Foundation
import CoreData


extension OpenAPS_Battery {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<OpenAPS_Battery> {
        return NSFetchRequest<OpenAPS_Battery>(entityName: "OpenAPS_Battery")
    }

    @NSManaged public var date: Date?
    @NSManaged public var display: Bool
    @NSManaged public var id: UUID?
    @NSManaged public var percent: Int16
    @NSManaged public var status: String?
    @NSManaged public var voltage: NSDecimalNumber?

}

extension OpenAPS_Battery : Identifiable {

}
