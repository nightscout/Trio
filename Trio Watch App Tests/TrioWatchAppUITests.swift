import XCTest

final class TrioWatchAppUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testMainViewElements() throws {
        // Test presence of main UI elements
        XCTAssertTrue(app.staticTexts["--"].exists) // Initial glucose value
        XCTAssertTrue(app.buttons["plus"].exists) // Treatment button

        // Test IOB and COB elements
        let iobElement = app.staticTexts.matching(identifier: "iob").firstMatch
        let cobElement = app.staticTexts.matching(identifier: "cob").firstMatch
        XCTAssertTrue(iobElement.exists)
        XCTAssertTrue(cobElement.exists)
    }

    func testTreatmentMenu() throws {
        // Open treatment menu
        app.buttons["plus"].tap()

        // Verify treatment options
        XCTAssertTrue(app.buttons["Carbs"].exists)
        XCTAssertTrue(app.buttons["Bolus"].exists)
        XCTAssertTrue(app.buttons["Meal Bolus"].exists)
    }

    func testBolusWorkflow() throws {
        // Open treatment menu
        app.buttons["plus"].tap()

        // Select bolus option
        app.buttons["Bolus"].tap()

        // Verify bolus input elements
        XCTAssertTrue(app.buttons["minus.circle.fill"].exists)
        XCTAssertTrue(app.buttons["plus.circle.fill"].exists)
        XCTAssertTrue(app.buttons["Log Bolus"].exists)
    }

    func testCarbsWorkflow() throws {
        // Open treatment menu
        app.buttons["plus"].tap()

        // Select carbs option
        app.buttons["Carbs"].tap()

        // Verify carbs input elements
        XCTAssertTrue(app.buttons["minus.circle.fill"].exists)
        XCTAssertTrue(app.buttons["plus.circle.fill"].exists)
        XCTAssertTrue(app.buttons["Log Carbs"].exists)
    }
}
