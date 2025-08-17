import CoreMotion
import Foundation
import Swinject

protocol ActivityDetectionDelegate: AnyObject {
    func activityDetectionManager(_ manager: ActivityDetectionManager, didDetectActivity activity: ActivityType)
    func activityDetectionManager(_ manager: ActivityDetectionManager, didStopActivity activity: ActivityType)
}

final class ActivityDetectionManager: Injectable {
    weak var delegate: ActivityDetectionDelegate?

    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var storage: FileStorage!

    private let motionManager = CMMotionActivityManager()
    private var activityQueue = OperationQueue()
    private var currentActivity: ActivityType?
    private var activityStartTime: Date?
    private var confirmationTimer: Timer?
    private var stopTimer: Timer?
    private var isMonitoring = false

    private var activityLog: [ActivityLogEntry] = []

    init(resolver: Resolver) {
        injectServices(resolver)
        loadActivityLog()
        setupActivityQueue()
    }

    private func setupActivityQueue() {
        activityQueue.maxConcurrentOperationCount = 1
        activityQueue.qualityOfService = .utility
    }

    private func loadActivityLog() {
        activityLog = storage.retrieve("activity_log.json", as: [ActivityLogEntry].self) ?? []
    }

    private func saveActivityLog() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            do {
                self.storage.save(self.activityLog, as: "activity_log.json")
            } catch {
                debug(.deviceManager, "Failed to save activity log: \(error)")
            }
        }
    }

    func startMonitoring() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            debug(.deviceManager, "Motion activity is not available on this device")
            return
        }

        guard !isMonitoring else {
            debug(.deviceManager, "Activity monitoring is already active")
            return
        }

        requestMotionPermission { [weak self] granted in
            guard granted else {
                debug(.deviceManager, "Motion permission not granted")
                return
            }

            self?.startActivityMonitoring()
        }
    }

    private func requestMotionPermission(completion: @escaping (Bool) -> Void) {
        guard CMMotionActivityManager.authorizationStatus() != .authorized else {
            completion(true)
            return
        }

        motionManager.queryActivityStarting(from: Date(), to: Date(), to: activityQueue) { _, _ in
            let authorized = CMMotionActivityManager.authorizationStatus() == .authorized
            DispatchQueue.main.async {
                completion(authorized)
            }
        }
    }

    private func startActivityMonitoring() {
        isMonitoring = true
        debug(.deviceManager, "Starting activity monitoring")

        motionManager.startActivityUpdates(to: activityQueue) { [weak self] activity in
            guard let self = self, let activity = activity else { return }

            DispatchQueue.main.async {
                self.processActivityUpdate(activity)
            }
        }
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        isMonitoring = false
        motionManager.stopActivityUpdates()

        confirmationTimer?.invalidate()
        confirmationTimer = nil

        stopTimer?.invalidate()
        stopTimer = nil

        if let currentActivity = currentActivity {
            finalizeActivityStop(currentActivity)
        }

        debug(.deviceManager, "Stopped activity monitoring")
    }

    private func processActivityUpdate(_ activity: CMMotionActivity) {
        let detectedActivity = detectPrimaryActivity(from: activity)

        if let detected = detectedActivity {
            handleActivityDetected(detected, confidence: activity.confidence)
        } else {
            handleNoActivityDetected()
        }
    }

    private func detectPrimaryActivity(from activity: CMMotionActivity) -> ActivityType? {
        let settings = settingsManager.settings

        guard activity.confidence == .high || activity.confidence == .medium else {
            return nil
        }

        if activity.running, settings.autoApplyRunningEnabled {
            return .running
        } else if activity.walking, settings.autoApplyWalkingEnabled {
            return .walking
        } else if activity.cycling, settings.autoApplyCyclingEnabled {
            return .cycling
        } else if activity.automotive || activity.unknown, settings.autoApplyOtherEnabled {
            return .other
        }

        return nil
    }

    private func handleActivityDetected(_ activity: ActivityType, confidence _: CMMotionActivityConfidence) {
        let now = Date()

        if currentActivity != activity {
            if let currentActivity = currentActivity {
                finalizeActivityStop(currentActivity)
            }

            currentActivity = activity
            activityStartTime = now

            confirmationTimer?.invalidate()

            DispatchQueue.main.async { [weak self] in
                self?.confirmationTimer = Timer.scheduledTimer(
                    withTimeInterval: TimeInterval((self?.settingsManager.settings.autoApplyMinimumDurationMinutes ?? 10) * 60),
                    repeats: false
                ) { [weak self] _ in
                    self?.confirmActivity(activity)
                }
            }

            debug(.deviceManager, "Detected \(activity.displayName) activity, waiting for confirmation")
        }

        stopTimer?.invalidate()
        stopTimer = nil
    }

    private func handleNoActivityDetected() {
        guard let currentActivity = currentActivity else { return }

        stopTimer?.invalidate()

        DispatchQueue.main.async { [weak self] in
            self?.stopTimer = Timer.scheduledTimer(
                withTimeInterval: TimeInterval((self?.settingsManager.settings.autoApplyStopDurationMinutes ?? 5) * 60),
                repeats: false
            ) { [weak self] _ in
                self?.finalizeActivityStop(currentActivity)
            }
        }
    }

    private func confirmActivity(_ activity: ActivityType) {
        guard currentActivity == activity else { return }

        let overrideName = getOverrideName(for: activity)
        guard !overrideName.isEmpty else {
            debug(.deviceManager, "No override configured for \(activity.displayName)")
            return
        }

        debug(.deviceManager, "Confirmed \(activity.displayName) activity, applying override: \(overrideName)")
        delegate?.activityDetectionManager(self, didDetectActivity: activity)

        if let startTime = activityStartTime {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let logEntry = ActivityLogEntry(
                    activityType: activity,
                    startDate: startTime,
                    overrideName: overrideName
                )
                self.activityLog.append(logEntry)
                self.saveActivityLog()
            }
        }
    }

    private func finalizeActivityStop(_ activity: ActivityType) {
        confirmationTimer?.invalidate()
        confirmationTimer = nil

        stopTimer?.invalidate()
        stopTimer = nil

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let index = self.activityLog.lastIndex(where: { $0.activityType == activity && $0.endDate == nil }) {
                self.activityLog[index] = ActivityLogEntry(
                    id: self.activityLog[index].id,
                    activityType: self.activityLog[index].activityType,
                    startDate: self.activityLog[index].startDate,
                    endDate: Date(),
                    overrideName: self.activityLog[index].overrideName
                )
                self.saveActivityLog()
            }
        }

        currentActivity = nil
        activityStartTime = nil

        debug(.deviceManager, "Stopped \(activity.displayName) activity")
        delegate?.activityDetectionManager(self, didStopActivity: activity)
    }

    private func getOverrideName(for activity: ActivityType) -> String {
        let settings = settingsManager.settings
        switch activity {
        case .walking:
            return settings.autoApplyWalkingOverride
        case .running:
            return settings.autoApplyRunningOverride
        case .cycling:
            return settings.autoApplyCyclingOverride
        case .other:
            return settings.autoApplyOtherOverride
        }
    }

    func getActivityLog() -> [ActivityLogEntry] {
        activityLog.sorted { $0.startDate > $1.startDate }
    }

    func clearActivityLog() {
        activityLog.removeAll()
        saveActivityLog()
    }

    var isActivityAvailable: Bool {
        CMMotionActivityManager.isActivityAvailable()
    }

    var authorizationStatus: CMAuthorizationStatus {
        CMMotionActivityManager.authorizationStatus()
    }
}
