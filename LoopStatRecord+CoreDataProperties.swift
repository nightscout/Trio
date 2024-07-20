//
//  LoopStatRecord+CoreDataProperties.swift
//  FreeAPS
//
//  Created by Cengiz Deniz on 21.07.24.
//
//

import Foundation
import CoreData


extension LoopStatRecord {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<LoopStatRecord> {
        return NSFetchRequest<LoopStatRecord>(entityName: "LoopStatRecord")
    }

    @NSManaged public var duration: Double
    @NSManaged public var end: Date?
    @NSManaged public var interval: Double
    @NSManaged public var loopStatus: String?
    @NSManaged public var start: Date?

}

extension LoopStatRecord : Identifiable {

}
