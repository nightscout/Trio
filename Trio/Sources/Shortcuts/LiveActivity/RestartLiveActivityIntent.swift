import AppIntents
import Foundation

/// App Intent used to restart the live activity via Apple Shortcuts automation.
/// When invoked, this intent instantiates a RestartLiveActivityIntentRequest, which has its
/// dependencies injected via Swinject, and calls the restart functionality.
@available(iOS 16.2, *) struct RestartLiveActivityIntent: LiveActivityIntent {
    /// Title of the action in the Shortcuts app.
    static var title = LocalizedStringResource("Restart Live Activity")

    /// Description of the action in the Shortcuts app.
    static var description = IntentDescription(.init("Restarts Trio's Live Activity"))

    /// Performs the intent by triggering the live activity restart.
    ///
    /// This method creates an instance of RestartLiveActivityIntentRequest (which inherits from BaseIntentsRequest)
    /// so that dependency injection provides the required services, then calls its restart functionality.
    ///
    /// - Returns: An intent result indicating success.
    @MainActor func perform() async throws -> some ReturnsValue<String> {
        let request = RestartLiveActivityIntentRequest()
        do {
            try await request.performRestart()
        } catch {
            debug(.default, "Error restarting Live Activity: \(error)")
        }
        return .result(value: String(localized: "Trio Live Activity restarted successfully."))
    }
}
