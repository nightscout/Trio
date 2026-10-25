import Foundation
import Testing
import UIKit

@testable import Trio

@Suite("Core Data waits for protected data") struct CoreDataProtectedDataTests {
    @MainActor private final class Flag {
        var value: Bool
        init(_ value: Bool) { self.value = value }
    }

    @Test("Returns at once when protected data is available") @MainActor func availableReturnsImmediately() async {
        let center = Foundation.NotificationCenter()
        await CoreDataStack.waitForProtectedData(isAvailable: { true }, notificationCenter: center)
    }

    @Test("Waits until protected data becomes available") @MainActor func waitsForUnlock() async throws {
        let center = Foundation.NotificationCenter()
        let finished = Flag(false)
        let task = Task { @MainActor in
            await CoreDataStack.waitForProtectedData(isAvailable: { false }, notificationCenter: center)
            finished.value = true
        }

        try await Task.sleep(for: .milliseconds(200))
        #expect(!finished.value)

        center.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
        await task.value
        #expect(finished.value)
    }

    @Test("An unlock during the check is not missed") @MainActor func unlockDuringCheck() async {
        let center = Foundation.NotificationCenter()
        let checks = Flag(false)
        // First check says locked, the re-check after adding the observer says unlocked
        await CoreDataStack.waitForProtectedData(
            isAvailable: {
                defer { checks.value = true }
                return checks.value
            },
            notificationCenter: center
        )
    }
}
