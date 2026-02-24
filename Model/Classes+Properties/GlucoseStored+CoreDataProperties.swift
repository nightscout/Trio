//
//  GlucoseStored+CoreDataProperties.swift
//  Trio
//
//  Created by Cengiz Deniz on 24.02.26.
//
//

import Foundation
import CoreData


extension GlucoseStored {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<GlucoseStored> {
        return NSFetchRequest<GlucoseStored>(entityName: "GlucoseStored")
    }

    @NSManaged public var date: Date?
    @NSManaged public var direction: String?
    @NSManaged public var glucose: Int16
    @NSManaged public var id: UUID?
    @NSManaged public var isManual: Bool
    @NSManaged public var isUploadedToHealth: Bool
    @NSManaged public var isUploadedToNS: Bool
    @NSManaged public var isUploadedToTidepool: Bool
    @NSManaged public var smoothedGlucose: NSDecimalNumber?

}

extension GlucoseStored : Identifiable {

}
