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
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

        // Start background task
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "Restart Live Activity") {
            Task { @MainActor in
                if backgroundTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                    backgroundTaskID = .invalid
                    debug(.default, "Background task expired and ended.")
                }
            }
        }

        guard backgroundTaskID != .invalid else {
            debug(.default, "Failed to start background task.")
            return
        }

        debug(.default, "Background task started: \(backgroundTaskID)")

        await liveActivityManager.restartActivityFromLiveActivityIntent()

        // Ensure background task ends properly
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            debug(.default, "Background task ended successfully.")
            backgroundTaskID = .invalid
        }
    }
}
