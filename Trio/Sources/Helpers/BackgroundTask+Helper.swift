import UIKit

/// Ends a background task safely and ensures it is not called multiple times.
///
/// - Parameter taskID: The background task identifier to be ended.
func endBackgroundTaskSafely(_ taskID: inout UIBackgroundTaskIdentifier, taskName: String = "Unnamed Task") {
    if taskID != .invalid {
        UIApplication.shared.endBackgroundTask(taskID)
        debug(.default, "Background task '\(taskName)' ended successfully.")
        taskID = .invalid
    } else {
        debug(.default, "Background task '\(taskName)' was already invalid or ended.")
    }
}

/// Starts a background task and handles its expiration safely.
///
/// - Parameter name: The background task name.
func startBackgroundTask(withName name: String) -> UIBackgroundTaskIdentifier {
    var taskID = UIBackgroundTaskIdentifier.invalid

    taskID = UIApplication.shared.beginBackgroundTask(withName: name) {
        Task { @MainActor in
            endBackgroundTaskSafely(&taskID, taskName: name)
        }
    }

    return taskID
}
