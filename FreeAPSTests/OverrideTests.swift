//
//  OverrideTests.swift
//  FreeAPSTests
//
//  Created by Pierre LAGARDE on 05/05/2024.
//
import CoreData
@testable import FreeAPS
import Swinject
import XCTest

final class OverrideTests: XCTestCase, Injectable {
    var overrideTestStorage: OverrideStorage!
    let resolver = FreeAPSApp().resolver
    var coreDataStack: CoreDataStack?

    override func setUp() {
        coreDataStack = TestCoreData()
        (resolver as! Container)
            .register(OverrideStorage.self, name: "testOverrideStorage") { r in
                BaseOverrideStorage(resolver: r, managedObjectContext: self.coreDataStack!.persistentContainer.viewContext) }

        overrideTestStorage = resolver.resolve(OverrideStorage.self, name: "testOverrideStorage")
        injectServices(resolver)
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
        overrideTestStorage = nil
        coreDataStack = nil
    }

    func testAddOverridePreset() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.

        // new override preset :
        let op = OverrideProfile(name: "test 1", percentage: 120, reason: "test 1")

        overrideTestStorage.storeOverridePresets([op])
        XCTAssertTrue(overrideTestStorage.presets().count == 1)
        XCTAssertTrue(overrideTestStorage.presets().first?.percentage == 120)
        XCTAssertNil(overrideTestStorage.presets().first?.date)

        let op2 = OverrideProfile(name: "test 2", percentage: 80, reason: "test 2")
        let op3 = OverrideProfile(name: "test 3", percentage: 200, reason: "test 3")
        overrideTestStorage.storeOverridePresets([op2, op3])
        XCTAssertTrue(overrideTestStorage.presets().count == 3)
    }

    func testUpdateOverridePreset() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.

        // new override preset :
        let op = OverrideProfile(name: "test 1", percentage: 120, reason: "test 1")

        overrideTestStorage.storeOverridePresets([op])
        var opUpdate = overrideTestStorage.presets().first
        opUpdate?.percentage = 150
        overrideTestStorage.storeOverridePresets([opUpdate!])
        XCTAssertTrue(overrideTestStorage.presets().count == 1)
        XCTAssertTrue(overrideTestStorage.presets().first?.percentage == 150)
    }

    func testRemoveOverridePreset() {
        // new override preset :
        let op = OverrideProfile(name: "test 1", percentage: 120, reason: "test 1")

        overrideTestStorage.storeOverridePresets([op])
        XCTAssertTrue(overrideTestStorage.presets().count == 1)
        let id = overrideTestStorage.presets().first(where: { $0.name == "test 1" })?.id
        overrideTestStorage.deleteOverridePreset(id!)
        XCTAssertTrue(overrideTestStorage.presets().isEmpty)
    }

    func testAddOverride() {
        let op = OverrideProfile(createdAt: Date(), duration: 20, percentage: 110, reason: "test 1")
        let op2 = OverrideProfile(
            createdAt: Date().addingTimeInterval(-10.minutes),
            duration: 10,
            percentage: 120,
            reason: "test 2"
        )
        let op3 = OverrideProfile(
            createdAt: Date().addingTimeInterval(-2.days.timeInterval),
            percentage: 20,
            reason: "test 3"
        )

        overrideTestStorage.storeOverride([op, op2, op3])

        XCTAssertTrue(overrideTestStorage.recent().count == 2)
        XCTAssertTrue(overrideTestStorage.recent().last!?.duration == 10)
        XCTAssertTrue(overrideTestStorage.current()?.percentage == 110)
    }

    func testUpdateOverride() {
        let op = OverrideProfile(createdAt: Date(), duration: 20, percentage: 110, reason: "test 1")

        overrideTestStorage.storeOverride([op])
        var opUpdate = overrideTestStorage.current()!
        opUpdate.duration = nil // force to be indefinate
        overrideTestStorage.storeOverride([opUpdate])
        XCTAssertNil(overrideTestStorage.current()?.duration)
        XCTAssertTrue(overrideTestStorage.current()?.indefinite == true)
    }

    func testCancelOverride() {
        let op = OverrideProfile(
            createdAt: Date().addingTimeInterval(-10.minutes),
            duration: 20,
            percentage: 110,
            reason: "test 1"
        )

        overrideTestStorage.storeOverride([op])
        let durationFinal = overrideTestStorage.cancelCurrentOverride()!
        XCTAssertNil(overrideTestStorage.current())
        XCTAssertLessThan(durationFinal, 1)
    }

    func testApplyOverrideProfile() {
        let op = OverrideProfile(name: "test 1", indefinite: true, percentage: 120, reason: "test 1")
        overrideTestStorage.storeOverridePresets([op])

//        let ov = OverrideProfile(createdAt: Date(), indefinite: true, percentage: 10, reason: "test 2")
//        overrideTestStorage.storeOverride([ov])

        let presetId = overrideTestStorage.presets().first?.id

        let date: Date = overrideTestStorage.applyOverridePreset(presetId!)!

        XCTAssertTrue(overrideTestStorage.current()?.percentage == 120)
        XCTAssertTrue(overrideTestStorage.current()?.createdAt == date)

        let op2 = OverrideProfile(name: "test 2", duration: 20, percentage: 10, reason: "test 2")
        overrideTestStorage.storeOverridePresets([op2])

        let presetId2 = overrideTestStorage.presets().first(where: { $0.name == "test 2" })!.id

        _ = overrideTestStorage.applyOverridePreset(presetId2)

        XCTAssertTrue(overrideTestStorage.recent().count == 2)
        XCTAssertTrue(overrideTestStorage.recent().last??.indefinite == false)
        if let duration = overrideTestStorage.recent().last??.duration {
            XCTAssertLessThan(duration, 1)
        } else {
            XCTAssert(false)
        }
        XCTAssertTrue(overrideTestStorage.current()?.percentage == 10)
    }
}
