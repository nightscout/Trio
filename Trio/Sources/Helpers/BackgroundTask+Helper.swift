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
    // Use a local copy of the taskID for the expiration handler
    let taskID = UIApplication.shared.beginBackgroundTask(withName: name) { [taskID = UIBackgroundTaskIdentifier.invalid] in
        // Create a new Task that takes the value of the taskID as a parameter
        // and does not use the captured variable
        Task { @MainActor in
            // Since we can no longer change the original taskID,
            // we simply end the Task with the given ID
            if taskID != .invalid {
                UIApplication.shared.endBackgroundTask(taskID)
                debug(.default, "Background task '\(name)' ended in expiration handler.")
            }
        }
    }

    debug(.default, "Background task '\(name)' started with ID: \(taskID)")
    return taskID
}
