import Combine
import Foundation
import Observation
import SwiftUI

extension ISFTiersEditor {
    @Observable final class StateModel: BaseStateModel<Provider> {
        var enabled: Bool = false
        var tiers: [InsulinSensitivityTier] = []
        var initialEnabled: Bool = false
        var initialTiers: [InsulinSensitivityTier] = []
        var shouldDisplaySaving: Bool = false

        private(set) var units: GlucoseUnits = .mgdL

        var hasChanges: Bool {
            enabled != initialEnabled || tiers != initialTiers
        }

        var canAddTier: Bool {
            guard let lastTier = tiers.last else { return true }
            return lastTier.bgMax < 400
        }

        override func subscribe() {
            units = settingsManager.settings.units

            let settings = provider.tiersSettings
            enabled = settings.enabled
            tiers = settings.tiers.isEmpty ? InsulinSensitivityTier.defaultTiers : settings.tiers

            initialEnabled = enabled
            initialTiers = tiers
        }

        func addTier() {
            let newMin = tiers.last?.bgMax ?? 0
            let newMax = min(newMin + 50, 400)
            let newTier = InsulinSensitivityTier(bgMin: newMin, bgMax: newMax, isfMultiplier: 1.0)
            tiers.append(newTier)
        }

        func removeTier(at offsets: IndexSet) {
            guard tiers.count > 1 else { return }
            tiers.remove(atOffsets: offsets)
        }

        func save() {
            guard hasChanges else { return }
            shouldDisplaySaving = true

            let settings = InsulinSensitivityTiers(enabled: enabled, tiers: tiers)
            provider.saveTiersSettings(settings)

            initialEnabled = enabled
            initialTiers = tiers

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.shouldDisplaySaving = false
            }
        }

        /// Format a BG value for display respecting the user's preferred units
        func formatBG(_ value: Decimal) -> String {
            if units == .mmolL {
                let mmol = value.asMmolL
                return "\(mmol)"
            } else {
                return "\(value)"
            }
        }

        /// Format the multiplier as a percentage string
        func formatMultiplier(_ value: Decimal) -> String {
            "\(value * 100)%"
        }
    }
}

extension ISFTiersEditor.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}
