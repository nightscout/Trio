//
//  TestCoreData.swift
//  FreeAPSTests
//
//  Created by Pierre LAGARDE on 05/05/2024.
//
import CoreData
@testable import FreeAPS
import Swinject
import XCTest

final class TestCoreData: CoreDataStack {
    override init() {
        super.init()
        let persistentStoreDescription = NSPersistentStoreDescription()
        persistentStoreDescription.type = NSInMemoryStoreType
        let container = NSPersistentContainer(name: CoreDataStack.modelName, managedObjectModel: CoreDataStack.model)

        container.persistentStoreDescriptions = [persistentStoreDescription]

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }
        persistentContainer = container
    }
}
