// import Foundation
//
// extension ComputedBGTargets {
//    func targetEntry(for time: Date = Date()) -> ComputedBGTargetEntry? {
//        // Assumes targets are sorted by start/offset ascending, wrap at midnight
//        let nowMinutes = Calendar.current.component(.hour, from: time) * 60 +
//            Calendar.current.component(.minute, from: time)
//        // Find last entry with offset <= nowMinutes
//        return targets.last(where: { $0.offset <= nowMinutes }) ?? targets.first
//    }
// }
