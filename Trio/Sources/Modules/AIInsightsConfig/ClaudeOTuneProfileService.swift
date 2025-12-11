import Combine
import Foundation
import LoopKit

/// Service for applying Claude-o-Tune recommendations to the user's profile
/// Handles backup, apply, and undo operations with safety checks
final class ClaudeOTuneProfileService {
    // MARK: - Types

    struct ProfileBackup: Codable {
        let id: UUID
        let createdAt: Date
        let basalProfile: [BasalProfileEntry]
        let insulinSensitivities: InsulinSensitivities
        let carbRatios: CarbRatios
        let reason: String

        var formattedDate: String {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: createdAt)
        }
    }

    struct ApplyResult {
        let success: Bool
        let appliedChanges: [String]
        let failedChanges: [String]
        let error: String?
        let backupId: UUID?
    }

    enum ApplyError: LocalizedError {
        case noChangesSelected
        case backupFailed
        case basalSyncFailed(String)
        case storageFailed(String)
        case invalidRecommendation

        var errorDescription: String? {
            switch self {
            case .noChangesSelected:
                return "No changes selected to apply"
            case .backupFailed:
                return "Failed to create profile backup"
            case .basalSyncFailed(let reason):
                return "Failed to sync basal rates with pump: \(reason)"
            case .storageFailed(let reason):
                return "Failed to save profile: \(reason)"
            case .invalidRecommendation:
                return "Invalid recommendation data"
            }
        }
    }

    // MARK: - Constants

    private static let backupsKey = "ClaudeOTune.profileBackups"
    private static let maxBackups = 10

    // MARK: - Dependencies

    @Injected() private var storage: FileStorage!
    @Injected() private var deviceManager: DeviceDataManager!
    @Injected() private var nightscout: NightscoutManager!

    // MARK: - Backup Management

    /// Create a backup of the current profile before applying changes
    func createBackup(reason: String) -> ProfileBackup? {
        guard let basalProfile = storage.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self),
              let insulinSensitivities = storage.retrieve(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self),
              let carbRatios = storage.retrieve(OpenAPS.Settings.carbRatios, as: CarbRatios.self)
        else {
            return nil
        }

        let backup = ProfileBackup(
            id: UUID(),
            createdAt: Date(),
            basalProfile: basalProfile,
            insulinSensitivities: insulinSensitivities,
            carbRatios: carbRatios,
            reason: reason
        )

        // Save to backups list
        var backups = getBackups()
        backups.insert(backup, at: 0)

        // Keep only the most recent backups
        if backups.count > Self.maxBackups {
            backups = Array(backups.prefix(Self.maxBackups))
        }

        saveBackups(backups)
        return backup
    }

    /// Get all saved backups
    func getBackups() -> [ProfileBackup] {
        guard let data = UserDefaults.standard.data(forKey: Self.backupsKey),
              let backups = try? JSONDecoder().decode([ProfileBackup].self, from: data)
        else {
            return []
        }
        return backups
    }

    /// Restore a profile from backup
    func restoreFromBackup(_ backup: ProfileBackup) async throws {
        // Restore basal profile (requires pump sync)
        try await syncBasalWithPump(backup.basalProfile)

        // Restore ISF and CR (direct storage)
        storage.save(backup.insulinSensitivities, as: OpenAPS.Settings.insulinSensitivities)
        storage.save(backup.carbRatios, as: OpenAPS.Settings.carbRatios)

        // Upload to Nightscout
        Task.detached(priority: .low) {
            try? await self.nightscout.uploadProfiles()
        }
    }

    /// Delete a specific backup
    func deleteBackup(_ backup: ProfileBackup) {
        var backups = getBackups()
        backups.removeAll { $0.id == backup.id }
        saveBackups(backups)
    }

    /// Delete all backups
    func deleteAllBackups() {
        UserDefaults.standard.removeObject(forKey: Self.backupsKey)
    }

    private func saveBackups(_ backups: [ProfileBackup]) {
        if let data = try? JSONEncoder().encode(backups) {
            UserDefaults.standard.set(data, forKey: Self.backupsKey)
        }
    }

    // MARK: - Apply Recommendations

    /// Apply selected recommendations from Claude-o-Tune
    /// - Parameters:
    ///   - recommendation: The full recommendation from Claude-o-Tune
    ///   - selectedBasalChanges: Indices of basal changes to apply
    ///   - selectedISFChanges: Indices of ISF changes to apply
    ///   - selectedCRChanges: Indices of CR changes to apply
    /// - Returns: Result of the apply operation
    func applyRecommendations(
        recommendation: ClaudeOTuneRecommendation,
        selectedBasalChanges: Set<Int>,
        selectedISFChanges: Set<Int>,
        selectedCRChanges: Set<Int>
    ) async throws -> ApplyResult {
        // Validate at least one change is selected
        guard !selectedBasalChanges.isEmpty || !selectedISFChanges.isEmpty || !selectedCRChanges.isEmpty else {
            throw ApplyError.noChangesSelected
        }

        // Create backup first
        guard let backup = createBackup(reason: "Before Claude-o-Tune changes") else {
            throw ApplyError.backupFailed
        }

        var appliedChanges: [String] = []
        var failedChanges: [String] = []

        // Apply basal changes
        if !selectedBasalChanges.isEmpty {
            do {
                try await applyBasalChanges(recommendation.recommendedProfile.basalRates, selectedIndices: selectedBasalChanges)
                appliedChanges.append("Basal rates (\(selectedBasalChanges.count) changes)")
            } catch {
                failedChanges.append("Basal rates: \(error.localizedDescription)")
            }
        }

        // Apply ISF changes
        if !selectedISFChanges.isEmpty {
            do {
                try applyISFChanges(recommendation.recommendedProfile.isfValues, selectedIndices: selectedISFChanges)
                appliedChanges.append("ISF (\(selectedISFChanges.count) changes)")
            } catch {
                failedChanges.append("ISF: \(error.localizedDescription)")
            }
        }

        // Apply CR changes
        if !selectedCRChanges.isEmpty {
            do {
                try applyCRChanges(recommendation.recommendedProfile.crValues, selectedIndices: selectedCRChanges)
                appliedChanges.append("Carb Ratios (\(selectedCRChanges.count) changes)")
            } catch {
                failedChanges.append("Carb Ratios: \(error.localizedDescription)")
            }
        }

        // Upload to Nightscout if any changes were applied
        if !appliedChanges.isEmpty {
            Task.detached(priority: .low) {
                try? await self.nightscout.uploadProfiles()
            }
        }

        return ApplyResult(
            success: failedChanges.isEmpty,
            appliedChanges: appliedChanges,
            failedChanges: failedChanges,
            error: failedChanges.isEmpty ? nil : failedChanges.joined(separator: "\n"),
            backupId: backup.id
        )
    }

    // MARK: - Individual Apply Methods

    private func applyBasalChanges(
        _ recommendations: [ClaudeOTuneRecommendation.BasalRateRecommendation],
        selectedIndices: Set<Int>
    ) async throws {
        // Get current basal profile
        guard var currentProfile = storage.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self) else {
            throw ApplyError.storageFailed("Could not read current basal profile")
        }

        // Apply selected changes
        for (index, rec) in recommendations.enumerated() {
            guard selectedIndices.contains(index) else { continue }

            // Find matching entry by time
            if let matchIndex = currentProfile.firstIndex(where: { $0.start.hasPrefix(rec.time) }) {
                // Update existing entry
                let entry = currentProfile[matchIndex]
                currentProfile[matchIndex] = BasalProfileEntry(
                    start: entry.start,
                    minutes: entry.minutes,
                    rate: rec.recommendedValue
                )
            }
        }

        // Sync with pump
        try await syncBasalWithPump(currentProfile)
    }

    private func syncBasalWithPump(_ profile: [BasalProfileEntry]) async throws {
        guard let pump = deviceManager?.pumpManager else {
            // No pump connected - just save locally
            storage.save(profile, as: OpenAPS.Settings.basalProfile)
            return
        }

        let syncValues = profile.map {
            RepeatingScheduleValue(startTime: TimeInterval($0.minutes * 60), value: Double($0.rate))
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pump.syncBasalRateSchedule(items: syncValues) { result in
                switch result {
                case .success:
                    self.storage.save(profile, as: OpenAPS.Settings.basalProfile)
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: ApplyError.basalSyncFailed(error.localizedDescription))
                }
            }
        }
    }

    private func applyISFChanges(
        _ recommendations: [ClaudeOTuneRecommendation.ISFRecommendation],
        selectedIndices: Set<Int>
    ) throws {
        // Get current ISF profile
        guard var currentProfile = storage.retrieve(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self) else {
            throw ApplyError.storageFailed("Could not read current ISF profile")
        }

        var sensitivities = currentProfile.sensitivities

        // Apply selected changes
        for (index, rec) in recommendations.enumerated() {
            guard selectedIndices.contains(index) else { continue }

            // Find matching entry by time
            if let matchIndex = sensitivities.firstIndex(where: { $0.start.hasPrefix(rec.time) }) {
                let entry = sensitivities[matchIndex]
                sensitivities[matchIndex] = InsulinSensitivityEntry(
                    sensitivity: rec.recommendedValue,
                    offset: entry.offset,
                    start: entry.start
                )
            }
        }

        currentProfile = InsulinSensitivities(
            units: currentProfile.units,
            userPreferredUnits: currentProfile.userPreferredUnits,
            sensitivities: sensitivities
        )

        storage.save(currentProfile, as: OpenAPS.Settings.insulinSensitivities)
    }

    private func applyCRChanges(
        _ recommendations: [ClaudeOTuneRecommendation.CRRecommendation],
        selectedIndices: Set<Int>
    ) throws {
        // Get current CR profile
        guard var currentProfile = storage.retrieve(OpenAPS.Settings.carbRatios, as: CarbRatios.self) else {
            throw ApplyError.storageFailed("Could not read current carb ratio profile")
        }

        var schedule = currentProfile.schedule

        // Apply selected changes
        for (index, rec) in recommendations.enumerated() {
            guard selectedIndices.contains(index) else { continue }

            // Find matching entry by time
            if let matchIndex = schedule.firstIndex(where: { $0.start.hasPrefix(rec.time) }) {
                let entry = schedule[matchIndex]
                schedule[matchIndex] = CarbRatioEntry(
                    start: entry.start,
                    offset: entry.offset,
                    ratio: rec.recommendedValue
                )
            }
        }

        currentProfile = CarbRatios(units: currentProfile.units, schedule: schedule)
        storage.save(currentProfile, as: OpenAPS.Settings.carbRatios)
    }
}
