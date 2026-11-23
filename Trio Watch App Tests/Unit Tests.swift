import SwiftUI
import Testing
@testable import Trio_Watch_App
import UIKit
import WatchKit

@Suite("Watch App Tests", .serialized) @MainActor final class TrioWatchAppTests {
    var watchState = WatchState()

    /// Lets main-queue work scheduled by WatchState (asyncAfter, async) run
    private func waitForMainQueue(_ seconds: Double) async throws {
        try await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
    }

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
    }

    @Test("Acknowledgment states transition correctly") func testAcknowledgmentStates() async throws {
        // Given - Initial state
        #expect(watchState.acknowledgementStatus == .pending)
        #expect(!watchState.showAcknowledgmentBanner)

        // When/Then - Success acknowledgment
        watchState.handleAcknowledgment(success: true, message: "Success")
        #expect(watchState.acknowledgementStatus == .success)
        #expect(watchState.acknowledgmentMessage == "Success")
        try await waitForMainQueue(0.5)
        #expect(watchState.showAcknowledgmentBanner)

        // When/Then - Failure acknowledgment
        watchState.handleAcknowledgment(success: false, message: "Error")
        #expect(watchState.acknowledgementStatus == .failure)
        #expect(watchState.acknowledgmentMessage == "Error")
    }

    // MARK: - Reachability must not touch entries in progress

    @Test("Phone reconnecting keeps the bolus being confirmed") func testReconnectKeepsBolusEntry() throws {
        // Given - the user is on the confirm screen, partway through dialing the crown
        watchState.bolusAmount = 3.0
        watchState.carbsAmount = 20
        watchState.confirmationProgress = 0.5

        // When - raising the wrist reconnects the phone
        watchState.handleReachabilityChange(isReachable: false)
        watchState.handleReachabilityChange(isReachable: true)

        // Then - the confirmed amount is still the one the user entered, not 0 U
        #expect(watchState.bolusAmount == 3.0)
        #expect(watchState.carbsAmount == 20)
        #expect(watchState.confirmationProgress == 0.5)
    }

    // MARK: - Bolus requests that must not be sent

    @Test("Zero bolus is refused on the watch", arguments: [
        Decimal(0),
        Decimal(-1)
    ]) func testZeroBolusRefused(amount: Decimal) async throws {
        watchState.sendBolusRequest(amount)

        #expect(watchState.acknowledgementStatus == .failure)
        #expect(watchState.acknowledgmentMessage == WatchState.invalidBolusAmountMessage)
        try await waitForMainQueue(0.5)
        #expect(!watchState.showCommsAnimation)
        #expect(watchState.showAcknowledgmentBanner)
    }

    @Test("Bolus with the phone unreachable says nothing was sent") func testUnreachableBolus() async throws {
        watchState.session = nil

        watchState.sendBolusRequest(3)

        #expect(watchState.acknowledgementStatus == .failure)
        #expect(watchState.acknowledgmentMessage == WatchState.phoneUnreachableMessage)
        try await waitForMainQueue(0.5)
        #expect(!watchState.showCommsAnimation)
        #expect(watchState.showAcknowledgmentBanner)
    }

    @Test("Other treatment requests with the phone unreachable say nothing was sent") func testUnreachableTreatments() throws {
        watchState.session = nil
        let requests: [() -> Void] = [
            { self.watchState.sendCarbsRequest(20) },
            { self.watchState.sendCancelOverrideRequest() },
            { self.watchState.sendActivateOverrideRequest(presetName: "Exercise") },
            { self.watchState.sendCancelTempTargetRequest() },
            { self.watchState.sendActivateTempTargetRequest(presetName: "Eating soon") }
        ]

        for request in requests {
            watchState.acknowledgementStatus = .pending
            watchState.acknowledgmentMessage = ""
            request()
            #expect(watchState.acknowledgementStatus == .failure)
            #expect(watchState.acknowledgmentMessage == WatchState.phoneUnreachableMessage)
        }
    }

    // MARK: - Waiting for the phone's answer

    @Test("Processing ends with a check-your-phone message when the phone never answers") func testAcknowledgmentTimeout() async throws {
        watchState.beginAwaitingAcknowledgment(timeout: 0.1)
        #expect(watchState.showCommsAnimation)
        #expect(watchState.acknowledgementStatus == .pending)

        try await waitForMainQueue(0.6)

        #expect(!watchState.showCommsAnimation)
        #expect(watchState.acknowledgementStatus == .failure)
        #expect(watchState.acknowledgmentMessage == WatchState.noAnswerMessage)
        #expect(watchState.showAcknowledgmentBanner)
    }

    @Test("An answer from the phone cancels the timeout") func testAcknowledgmentCancelsTimeout() async throws {
        watchState.beginAwaitingAcknowledgment(timeout: 0.1)

        watchState.handleAcknowledgment(success: true, message: "Bolus enacted successfully.")
        try await waitForMainQueue(0.6)

        #expect(watchState.acknowledgementStatus == .success)
        #expect(watchState.acknowledgmentMessage == "Bolus enacted successfully.")
    }

    @Test("A send error ends processing with the check-your-phone message") func testSendErrorEndsProcessing() async throws {
        watchState.beginAwaitingAcknowledgment(timeout: 60)

        // What the sendMessage error handler does
        watchState.handleMissingAcknowledgment()

        #expect(watchState.acknowledgementStatus == .failure)
        #expect(watchState.acknowledgmentMessage == WatchState.noAnswerMessage)
        try await waitForMainQueue(0.5)
        #expect(!watchState.showCommsAnimation)
    }

    @Test("A late timeout does not overwrite an answer already shown") func testMissingAcknowledgmentAfterAnswer() async throws {
        watchState.beginAwaitingAcknowledgment(timeout: 60)
        watchState.handleAcknowledgment(success: true, message: "Bolus enacted successfully.")
        try await waitForMainQueue(0.3)

        watchState.handleMissingAcknowledgment()

        #expect(watchState.acknowledgementStatus == .success)
        #expect(watchState.acknowledgmentMessage == "Bolus enacted successfully.")
    }

    // MARK: - Entries expire after 2 minutes

    private let entryStart = Date(timeIntervalSince1970: 1_800_000_000)

    /// An entry on the confirm screen: 20 g carbs and 3 U, last edited at `entryStart`
    private func enterMealBolus() {
        watchState.carbsAmount = 20
        watchState.bolusAmount = 3.0
        watchState.confirmationProgress = 0.5
        watchState.markEntryEdited(at: entryStart)
    }

    private func expectEntryCleared() {
        #expect(watchState.bolusAmount == 0)
        #expect(watchState.carbsAmount == 0)
        #expect(watchState.confirmationProgress == 0)
        #expect(watchState.entryEditedAt == nil)
    }

    @Test("An entry is fresh for 2 minutes after its last edit") func testEntryFreshness() throws {
        #expect(!watchState.isEntryFresh(at: entryStart), "no entry has been edited yet")

        watchState.markEntryEdited(at: entryStart)

        #expect(watchState.isEntryFresh(at: entryStart.addingTimeInterval(119)))
        #expect(watchState.isEntryFresh(at: entryStart.addingTimeInterval(120)))
        #expect(!watchState.isEntryFresh(at: entryStart.addingTimeInterval(121)))

        // Editing again restarts the clock
        watchState.markEntryEdited(at: entryStart.addingTimeInterval(100))
        #expect(watchState.isEntryFresh(at: entryStart.addingTimeInterval(200)))
    }

    @Test("Confirming an entry older than 2 minutes sends nothing and clears it") func testExpiredEntryNotSent() throws {
        enterMealBolus()

        watchState.sendConfirmedEntry(bolusAmount: 3.0, at: entryStart.addingTimeInterval(121))

        // The expired message, not "phone unreachable", shows nothing was attempted
        #expect(watchState.acknowledgementStatus == .failure)
        #expect(watchState.acknowledgmentMessage == WatchState.entryExpiredMessage)
        expectEntryCleared()
    }

    @Test("Confirming an entry with no recorded edit sends nothing") func testUneditedEntryNotSent() throws {
        watchState.bolusAmount = 3.0

        watchState.sendConfirmedEntry(bolusAmount: 3.0, at: entryStart)

        #expect(watchState.acknowledgmentMessage == WatchState.entryExpiredMessage)
        expectEntryCleared()
    }

    @Test("Confirming a fresh entry sends it and clears it") func testFreshEntrySent() throws {
        enterMealBolus()
        // No phone in tests: reaching the "unreachable" refusal proves the send was attempted
        watchState.session = nil

        watchState.sendConfirmedEntry(bolusAmount: 3.0, at: entryStart.addingTimeInterval(60))

        #expect(watchState.acknowledgmentMessage == WatchState.phoneUnreachableMessage)
        expectEntryCleared()
    }

    @Test("Logging carbs older than 2 minutes sends nothing") func testExpiredCarbsNotSent() throws {
        watchState.markEntryEdited(at: entryStart)

        watchState.sendCarbsEntry(20, at: entryStart.addingTimeInterval(121))

        #expect(watchState.acknowledgmentMessage == WatchState.entryExpiredMessage)
        expectEntryCleared()
    }

    @Test("Logging fresh carbs sends them") func testFreshCarbsSent() throws {
        watchState.markEntryEdited(at: entryStart)
        watchState.session = nil

        watchState.sendCarbsEntry(20, at: entryStart.addingTimeInterval(60))

        #expect(watchState.acknowledgmentMessage == WatchState.phoneUnreachableMessage)
        expectEntryCleared()
    }

    @Test("Returning to the app clears an entry older than 2 minutes") func testStaleEntryExpiresOnReturn() throws {
        enterMealBolus()

        #expect(!watchState.expireStaleEntry(at: entryStart.addingTimeInterval(120)))
        #expect(watchState.bolusAmount == 3.0)

        #expect(watchState.expireStaleEntry(at: entryStart.addingTimeInterval(121)))
        expectEntryCleared()
    }

    @Test("Returning to the app with no entry in progress changes nothing") func testNoEntryOnReturn() throws {
        #expect(!watchState.expireStaleEntry(at: entryStart))
    }
}

// MARK: - Bolus Confirmation Crown Hint Tests

/// The bolus confirmation screen fills its progress bar as the Digital Crown value goes up, and shows an arrow
/// icon in the toolbar saying which way to turn the crown. These tests check that arrow against the turn that
/// actually confirms, for every combination of the watch's wrist and Digital Crown settings.
@Suite("Bolus confirmation crown hint") struct BolusConfirmationCrownHintTests {
    /// Which way the crown turns, looking at the end of the crown from outside the watch.
    enum CrownTurn: Equatable {
        case clockwise
        case counterclockwise
    }

    /// The turn the hint icon tells the user to make.
    static func shownTurn(symbolName: String) -> CrownTurn? {
        switch symbolName {
        case "digitalcrown.arrow.clockwise.fill": return .clockwise
        case "digitalcrown.arrow.counterclockwise.fill": return .counterclockwise
        default: return nil
        }
    }

    /// The turn that raises the crown value and so fills the confirmation bar.
    ///
    /// watchOS reports crown rotation relative to the display, not the hardware: the value goes up when the edge
    /// of the crown nearest the screen rolls toward the top of the display, however the watch is worn. Looking at
    /// the end of the crown, that is clockwise when the crown sits on the right of the display and counterclockwise
    /// when it sits on the left. The Digital Crown setting is that side, as seen by the wearer, so the wrist does
    /// not change which way to turn.
    ///
    /// Left wrist with the crown on the right is the default, and the app already shows clockwise there.
    static func requiredTurn(crownOrientation: WKInterfaceDeviceCrownOrientation) -> CrownTurn {
        crownOrientation == .right ? .clockwise : .counterclockwise
    }

    @Test(
        "Crown hint arrow matches the turn that confirms a bolus",
        arguments: [WKInterfaceDeviceWristLocation.left, .right],
        [WKInterfaceDeviceCrownOrientation.left, .right]
    ) func crownHintMatchesRequiredTurn(
        wristLocation: WKInterfaceDeviceWristLocation,
        crownOrientation: WKInterfaceDeviceCrownOrientation
    ) throws {
        let symbolName = BolusConfirmationView.crownHintSymbolName(
            wristLocation: wristLocation,
            crownOrientation: crownOrientation
        )
        let shown = try #require(Self.shownTurn(symbolName: symbolName))
        let required = Self.requiredTurn(crownOrientation: crownOrientation)

        #expect(shown == required)
    }

    @Test(
        "Crown hint icon is a symbol watchOS can draw",
        arguments: [WKInterfaceDeviceWristLocation.left, .right],
        [WKInterfaceDeviceCrownOrientation.left, .right]
    ) func crownHintSymbolExists(
        wristLocation: WKInterfaceDeviceWristLocation,
        crownOrientation: WKInterfaceDeviceCrownOrientation
    ) {
        let symbolName = BolusConfirmationView.crownHintSymbolName(
            wristLocation: wristLocation,
            crownOrientation: crownOrientation
        )
        #expect(UIImage(systemName: symbolName) != nil)
    }

    @Test("A key a kit update adds to the CGM export keeps the watch's manager") func testSameSensorIgnoresNewKeys() throws {
        let g7 = try #require(watchCGMManagersByIdentifier["G7CGMManager"])
        let built: [String: Any] = ["sensorID": "ABC123", "activatedAt": Date(timeIntervalSince1970: 1000), "pairingCode": "1234"]
        var updated = built
        updated["calibrationAdviceSeen"] = false
        #expect(g7.sameSensor(built, updated))
        updated["sensorID"] = "XYZ789"
        #expect(!g7.sameSensor(built, updated))
        #expect(!g7.sameSensor(built, ["sensorID": "ABC123", "activatedAt": Date(timeIntervalSince1970: 1000)]))
    }
}
