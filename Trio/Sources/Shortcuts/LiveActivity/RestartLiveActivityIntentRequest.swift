import AppIntents
import Foundation
import UIKit

/// Request object that uses dependency injection to perform a live activity restart.
/// This class inherits from BaseIntentsRequest so that its dependencies (including liveActivityManager)
/// are automatically injected.
@available(iOS 16.2, *) final class RestartLiveActivityIntentRequest: BaseIntentsRequest {
    /// Triggers the live activity restart via the injected LiveActivityManager.
    ///
    /// - Throws: An error if the restart process fails.
    /// - Returns: Void upon successful restart.
    @MainActor func performRestart() async throws {
        // Start background task
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = startBackgroundTask(withName: "Restart Live Activity")

        guard backgroundTaskID != .invalid else {
            warning(.liveActivity, "Live Activity restart skipped, background task could not start")
            return
        }

        await liveActivityManager.restartActivityFromLiveActivityIntent()

        // Ensure background task ends properly
        endBackgroundTaskSafely(&backgroundTaskID, taskName: "Restart Live Activity")
    }
}
