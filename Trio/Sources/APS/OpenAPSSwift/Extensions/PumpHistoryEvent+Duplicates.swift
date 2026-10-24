import Foundation

public extension Array where Element == PumpHistoryEvent {
    /// Removes duplicate suspend and resume events, keeping the first of each timestamp.
    /// Trio applies this to the pump history before `IobGenerator.generate`.
    /// - Returns: A new array with duplicate suspend/resume events removed
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
