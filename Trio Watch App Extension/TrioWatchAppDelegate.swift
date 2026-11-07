import WatchKit

/// The CGM wakes the app through Bluetooth; each wake is held long enough for the sensor's re-connect, which keeps the
/// process past the sensor's advertising tail.
final class TrioWatchAppDelegate: NSObject, WKApplicationDelegate {
    /// Kept, not just their identities: WatchKit can hand a task over again, and completing one twice crashes.
    private var completed: [WKRefreshBackgroundTask] = []
    private static let bluetoothHold: TimeInterval = 25
    /// A held task older than this is from an earlier wake.
    private static let wakeLength: TimeInterval = 60
    /// One task held per wake: WatchKit delivers one for every Bluetooth message, dozens a second while the sensor
    /// pairs. The rest are completed on arrival.
    private var heldBluetoothTask: WKRefreshBackgroundTask?
    private var heldSince: Date?

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        // not always on main: a Bluetooth task can arrive on CoreBluetooth's queue, and all below is main-only
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.handle(backgroundTasks) }
            return
        }
        for task in backgroundTasks {
            if task is WKApplicationRefreshBackgroundTask {
                // the CGM's acquisition backstop (`WatchCGMHost`): a sensor connect still missing goes in now
                task.expirationHandler = { [weak self, weak task] in
                    let expire = { if let task { self?.complete(task) } }
                    if Thread.isMainThread { expire() } else { DispatchQueue.main.sync(execute: expire) }
                }
                WatchCGMHost.shared.recheckAcquisition()
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.complete(task) }
                continue
            }
            guard task is WKBluetoothAlertRefreshBackgroundTask else {
                complete(task)
                continue
            }
            if task === heldBluetoothTask { continue }
            if heldBluetoothTask != nil, let since = heldSince, Date().timeIntervalSince(since) < Self.wakeLength {
                complete(task)
                continue
            }
            heldBluetoothTask = task
            let since = Date()
            heldSince = since
            // the system may grant less than the hold: the task ends then, not later, and the grant is logged
            task.expirationHandler = { [weak self, weak task] in
                let expire = {
                    let granted = Date().timeIntervalSince(since)
                    WatchLogger.shared.debug(
                        .lifecycle,
                        String(format: "Bluetooth wake expired by the system after %.1f s", granted)
                    )
                    if let task { self?.release(task) }
                }
                if Thread.isMainThread { expire() } else { DispatchQueue.main.sync(execute: expire) }
            }
            // a reading in this wake arrives through the CGM delegate; the wake itself only checks
            WatchCGMHost.shared.recheckAcquisition()
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.bluetoothHold) { self.release(task) }
        }
    }

    /// Ends a held wake, by the hold or by the system's expiry, whichever comes first.
    private func release(_ task: WKRefreshBackgroundTask) {
        if heldBluetoothTask === task {
            heldBluetoothTask = nil
            heldSince = nil
        }
        complete(task)
    }

    private func complete(_ task: WKRefreshBackgroundTask) {
        guard !completed.contains(where: { $0 === task }) else { return }
        completed.append(task)
        if completed.count > 128 { completed.removeFirst(32) }
        task.setTaskCompletedWithSnapshot(false)
    }
}
