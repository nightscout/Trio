import CoreMotion
import Foundation
import SwiftUI

extension AutoApplyOverride {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var activityDetectionManager: ActivityDetectionManager!

        @Published var isEnabled: Bool = false
        @Published var walkingEnabled: Bool = false
        @Published var runningEnabled: Bool = false
        @Published var cyclingEnabled: Bool = false
        @Published var otherEnabled: Bool = false

        @Published var walkingOverride: String = ""
        @Published var runningOverride: String = ""
        @Published var cyclingOverride: String = ""
        @Published var otherOverride: String = ""

        @Published var minimumDurationMinutes: Int = 10
        @Published var stopDurationMinutes: Int = 5

        @Published var overridePresets: [OverrideStored] = []
        @Published var activityLog: [ActivityLogEntry] = []

        @Published var isActivityAvailable: Bool = false
        @Published var authorizationStatus: CMAuthorizationStatus = .notDetermined

        override func subscribe() {
            isEnabled = settingsManager.settings.autoApplyOverrideEnabled
            walkingEnabled = settingsManager.settings.autoApplyWalkingEnabled
            runningEnabled = settingsManager.settings.autoApplyRunningEnabled
            cyclingEnabled = settingsManager.settings.autoApplyCyclingEnabled
            otherEnabled = settingsManager.settings.autoApplyOtherEnabled

            walkingOverride = settingsManager.settings.autoApplyWalkingOverride
            runningOverride = settingsManager.settings.autoApplyRunningOverride
            cyclingOverride = settingsManager.settings.autoApplyCyclingOverride
            otherOverride = settingsManager.settings.autoApplyOtherOverride

            minimumDurationMinutes = settingsManager.settings.autoApplyMinimumDurationMinutes
            stopDurationMinutes = settingsManager.settings.autoApplyStopDurationMinutes

            subscribeSetting(\.autoApplyOverrideEnabled, on: $isEnabled) { [weak self] in
                self?.isEnabled = $0
                self?.updateActivityMonitoring()
            }

            subscribeSetting(\.autoApplyWalkingEnabled, on: $walkingEnabled) { walkingEnabled = $0 }
            subscribeSetting(\.autoApplyRunningEnabled, on: $runningEnabled) { runningEnabled = $0 }
            subscribeSetting(\.autoApplyCyclingEnabled, on: $cyclingEnabled) { cyclingEnabled = $0 }
            subscribeSetting(\.autoApplyOtherEnabled, on: $otherEnabled) { otherEnabled = $0 }

            subscribeSetting(\.autoApplyWalkingOverride, on: $walkingOverride) { walkingOverride = $0 }
            subscribeSetting(\.autoApplyRunningOverride, on: $runningOverride) { runningOverride = $0 }
            subscribeSetting(\.autoApplyCyclingOverride, on: $cyclingOverride) { cyclingOverride = $0 }
            subscribeSetting(\.autoApplyOtherOverride, on: $otherOverride) { otherOverride = $0 }

            subscribeSetting(\.autoApplyMinimumDurationMinutes, on: $minimumDurationMinutes) { minimumDurationMinutes = $0 }
            subscribeSetting(\.autoApplyStopDurationMinutes, on: $stopDurationMinutes) { stopDurationMinutes = $0 }

            loadData()
        }

        private func loadData() {
            overridePresets = provider.getOverridePresets()
            activityLog = provider.getActivityLog()
            isActivityAvailable = activityDetectionManager.isActivityAvailable
            authorizationStatus = activityDetectionManager.authorizationStatus
        }

        private func updateActivityMonitoring() {
            if isEnabled {
                activityDetectionManager.startMonitoring()
            } else {
                activityDetectionManager.stopMonitoring()
            }
        }

        func clearActivityLog() {
            provider.clearActivityLog()
            activityLog = []
        }

        func refreshData() {
            loadData()
        }
    }
}
