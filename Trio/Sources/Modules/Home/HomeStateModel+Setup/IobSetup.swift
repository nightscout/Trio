import Foundation
import UIKit

extension Home.StateModel {
    /// Fetch the most recent IoB value using the oref `iob` function. Call this function any time
    /// you want to update the displayed IoB, like on the arrival of a new pump event or at initialization
    func setupIobForDisplay() {
        Task {
            do {
                let at = Date()
                guard let iob = try await apsManager.iobForDisplay(at: at) else {
                    debug(.default, "Could not get iob for display (oref returned nil)")
                    // if more than 15 minutes have gone by since the last IoB update
                    // set it to nil
                    let lastRun = iobForDisplayUpdatedAt ?? .distantPast
                    if at.timeIntervalSince(lastRun) > (15 * 60) {
                        await updateIobForDisplay(iob: nil, at: at)
                    }
                    return
                }
                await updateIobForDisplay(iob: iob, at: at)
            } catch {
                debug(
                    .default,
                    "\(DebuggingIdentifiers.failed) Error setting up iob for display \(error)"
                )
            }
        }
    }

    /// Update IoB periodically. This function will update the displayed IoB in response
    /// to timer events. Internally, it has logic to reduce the frequency of updates as it is
    /// designed to capture typical decay from elapsed time. If there is something that
    /// changes IoB, like a new pump event, use `setupIobForDisplay` instead.
    /// Also, only update IoB when the app is in the foreground.
    func setupIobForDisplayOnTimer() {
        guard UIApplication.shared.applicationState == .active else {
            return
        }
        Task {
            let lastRun = iobForDisplayUpdatedAt ?? .distantPast
            // if we don't have an iob value re-run it more often
            let period = iobForDisplay == nil ? TimeInterval(1 * 60) : TimeInterval(5 * 60)
            if Date().timeIntervalSince(lastRun) > period {
                setupIobForDisplay()
            }
        }
    }

    /// Update the IoB state values. There is a small amount of logic to try to deal with
    /// updated values that happen concurrently by using the most recent results
    @MainActor func updateIobForDisplay(iob: Decimal?, at: Date) {
        // in case we get two calls at around the same time
        // make sure to only use the most recent result
        // unless the iobForDisplay isn't set and we have a result
        let lastRun = iobForDisplayUpdatedAt ?? .distantPast
        if at > lastRun || (iob != nil && iobForDisplay == nil) {
            iobForDisplay = iob
            iobForDisplayUpdatedAt = at
        }
    }
}
