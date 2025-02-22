import Foundation

extension Array where Element == PumpHistoryEvent {
    /// Removes duplicate PumpSuspend events from the array
    /// - Returns: A new array with duplicate suspend events removed
    func removingDuplicateSuspendResumeEvents() -> [PumpHistoryEvent] {
        var seenSuspendResume = Set<Date>()

        return filter { event in
            if event.type != .pumpSuspend, event.type != .pumpResume {
                return true
            }

            // Make suspend/resume events unique by timestamp
            return seenSuspendResume.insert(event.timestamp).inserted
        }
    }
}
