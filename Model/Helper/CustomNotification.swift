import Combine
import Foundation

extension Notification.Name {
    static let willUpdateOverrideConfiguration = Notification.Name("willUpdateOverrideConfiguration")
    static let didUpdateOverrideConfiguration = Notification.Name("didUpdateOverrideConfiguration")
    static let didUpdateCobIob = Notification.Name("didUpdateCobIob")
    static let liveActivityOrderDidChange = Notification.Name("liveActivityOrderDidChange")
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
