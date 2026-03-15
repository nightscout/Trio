import Combine
import Foundation

extension Notification.Name {
    static let willUpdateOverrideConfiguration = Notification.Name("willUpdateOverrideConfiguration")
    static let didUpdateOverrideConfiguration = Notification.Name("didUpdateOverrideConfiguration")
    static let willUpdateTempTargetConfiguration = Notification.Name("willUpdateTempTargetConfiguration")
    static let didUpdateTempTargetConfiguration = Notification.Name("didUpdateTempTargetConfiguration")
    static let liveActivityOrderDidChange = Notification.Name("liveActivityOrderDidChange")
    static let openFromGarminConnect = Notification.Name("Notification.Name.openFromGarminConnect")
}

func awaitNotification(_ name: Notification.Name) async {
    await withCheckedContinuation { continuation in
        var cancellable: AnyCancellable?

        // Create a Combine publisher that listens for notifications
        cancellable = Foundation.NotificationCenter.default
            .publisher(for: name)
            .sink { _ in
                // When the notification is received, resume the awaiting task
                continuation.resume()

                // Cancel the subscription after the continuation has resumed
                cancellable?.cancel()
            }
    }
}
