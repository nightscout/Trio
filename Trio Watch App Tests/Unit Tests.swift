import SwiftUICore
import Testing
@testable import Trio_Watch_App
import XCTest

@Suite("Watch App Tests") final class TrioWatchAppTests {
    var watchState = WatchState()

    // MARK: - Color Conversion Tests

    @Test("Hex string to color conversion") func testHexStringToColor() throws {
        // Given
        let whiteHex = "#FFFFFF"
        let blackHex = "#000000"
        let redHex = "#FF0000"
        let invalidHex = "invalid"

        // Then
        #expect(whiteHex.toColor() == Color.white)
        #expect(blackHex.toColor() == Color.black)
        #expect(redHex.toColor() == Color(red: 1, green: 0, blue: 0))
        #expect(invalidHex.toColor() == Color.black)
    }

    // MARK: - WatchState Tests

    @Test("WatchState initialization with default values") func testWatchStateInitialization() throws {
        #expect(watchState.currentGlucose == "--")
        #expect(watchState.currentGlucoseColorString == "#ffffff")
        #expect(watchState.glucoseValues.isEmpty)
        #expect(watchState.iob == "--")
        #expect(watchState.cob == "--")
        #expect(watchState.lastLoopTime == "--")
    }

    @Test("Bolus limits have correct default values") func testBolusLimits() throws {
        #expect(watchState.maxBolus == Decimal(10))
        #expect(watchState.bolusIncrement == Decimal(0.05))
    }

    @Test("Carb limits have correct default values") func testCarbLimits() throws {
        #expect(watchState.maxCarbs == Decimal(250))
        #expect(watchState.maxCOB == Decimal(120))
    }

    @Test("Bolus cancellation resets all related values") func testBolusCancellation() throws {
        // Given
        watchState.bolusProgress = 0.5
        watchState.activeBolusAmount = 5.0
        watchState.isBolusCanceled = false

        // When
        watchState.sendCancelBolusRequest()

        // Then
        #expect(watchState.isBolusCanceled)
        #expect(watchState.bolusProgress == 0)
        #expect(watchState.activeBolusAmount == 0)
    }

    @Test("Meal bolus combo state transitions work correctly") func testMealBolusComboState() throws {
        // Given - Initial state
        #expect(!watchState.isMealBolusCombo)
        #expect(watchState.mealBolusStep == .savingCarbs)

        // When - Setup meal bolus combo
        watchState.carbsAmount = 30
        watchState.bolusAmount = 3.0

        // Then - Test state transitions
        watchState.handleAcknowledgment(success: true, message: "Saving carbs...", isFinal: false)
        #expect(watchState.isMealBolusCombo)
        #expect(watchState.mealBolusStep == .savingCarbs)

        watchState.handleAcknowledgment(success: true, message: "Enacting bolus...", isFinal: false)
        #expect(watchState.isMealBolusCombo)
        #expect(watchState.mealBolusStep == .enactingBolus)

        watchState.handleAcknowledgment(success: true, message: "Carbs and bolus logged successfully", isFinal: true)
        #expect(!watchState.isMealBolusCombo)
    }

    @Test("Acknowledgment states transition correctly") func testAcknowledgmentStates() throws {
        // Given - Initial state
        #expect(watchState.acknowledgementStatus == .pending)
        #expect(!watchState.showAcknowledgmentBanner)

        // When/Then - Success acknowledgment
        watchState.handleAcknowledgment(success: true, message: "Success")
        #expect(watchState.acknowledgementStatus == .success)
        #expect(watchState.showAcknowledgmentBanner)
        #expect(watchState.acknowledgmentMessage == "Success")

        // When/Then - Failure acknowledgment
        watchState.handleAcknowledgment(success: false, message: "Error")
        #expect(watchState.acknowledgementStatus == .failure)
        #expect(watchState.showAcknowledgmentBanner)
        #expect(watchState.acknowledgmentMessage == "Error")
    }
}
