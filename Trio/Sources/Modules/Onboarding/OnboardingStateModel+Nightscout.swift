import Combine
import Foundation
import SwiftUI

// MARK: - Setup Nightscout Connection

extension Onboarding.StateModel {
    func connectToNightscout() {
        if let CheckURL = url.last, CheckURL == "/" {
            let fixedURL = url.dropLast()
            url = String(fixedURL)
        }

        guard let url = URL(string: url), self.url.hasPrefix("https://") else {
            message = "Invalid URL"
            isValidURL = false
            return
        }

        connecting = true
        isValidURL = true
        message = ""

        NightscoutAPI(url: url, secret: secret).checkConnection()
            .receive(on: DispatchQueue.main)
            .sink { completion in
                switch completion {
                case .finished: break
                case let .failure(error):
                    self.message = "Error: \(error.localizedDescription)"
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self.connecting = false
                }
            } receiveValue: {
                self.keychain.setValue(self.url, forKey: NightscoutConfig.Config.urlKey)
                self.keychain.setValue(self.secret, forKey: NightscoutConfig.Config.secretKey)
                self.isConnectedToNS = true
            }
            .store(in: &lifetime)
    }

    private var nightscoutAPI: NightscoutAPI? {
        guard let urlString = keychain.getValue(String.self, forKey: NightscoutConfig.Config.urlKey),
              let url = URL(string: urlString),
              let secret = keychain.getValue(String.self, forKey: NightscoutConfig.Config.secretKey)
        else {
            return nil
        }
        return NightscoutAPI(url: url, secret: secret)
    }

    func importSettingsFromNightscout(currentStep: Binding<OnboardingStep>) async {
        guard nightscoutAPI != nil, isConnectedToNS else {
            return
        }

        nightscoutImportStatus = .running

        do {
            guard let fetchedProfile = await nightscoutManager.importSettings() else {
                await MainActor.run {
                    nightscoutImportStatus = .failed
                }
                throw NSError(
                    domain: "ImportError",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Cannot find the default Nightscout Profile."]
                )
            }

            // determine, i.e. guesstimate, whether fetched values are mmol/L or mg/dL values
            let shouldConvertToMgdL = fetchedProfile.units.contains("mmol") || fetchedProfile.target_low
                .contains(where: { $0.value <= 39 }) || fetchedProfile.target_high.contains(where: { $0.value <= 39 })

            // Carb Ratios
            let carbratios = fetchedProfile.carbratio.map { carbratio in
                CarbRatioEntry(
                    start: carbratio.time,
                    offset: offset(carbratio.time) / 60,
                    ratio: carbratio.value
                )
            }

            if carbratios.contains(where: { $0.ratio <= 0 }) {
                await MainActor.run {
                    nightscoutImportStatus = .failed
                }
                throw NSError(
                    domain: "ImportError",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid Carb Ratio settings in Nightscout. Import aborted."]
                )
            }

            let carbratiosProfile = CarbRatios(units: .grams, schedule: carbratios)

            // Basal Profile
            let basals = fetchedProfile.basal.map { basal in
                BasalProfileEntry(
                    start: basal.time,
                    minutes: offset(basal.time) / 60,
                    rate: basal.value
                )
            }

            if basals.contains(where: { $0.rate <= 0 }) {
                await MainActor.run {
                    nightscoutImportStatus = .failed
                }
                throw NSError(
                    domain: "ImportError",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid Nightscout basal rates found. Import aborted."]
                )
            }

            if basals.reduce(0, { $0 + $1.rate }) <= 0 {
                await MainActor.run {
                    nightscoutImportStatus = .failed
                }
                throw NSError(
                    domain: "ImportError",
                    code: 4,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Invalid Nightscout basal rates found. Basal rate total cannot be 0 U/hr. Import aborted."
                    ]
                )
            }

            // Sensitivities
            let sensitivities = fetchedProfile.sens.map { sensitivity in
                InsulinSensitivityEntry(
                    sensitivity: shouldConvertToMgdL ? correctUnitParsingOffsets(sensitivity.value.asMgdL) : sensitivity
                        .value,
                    offset: offset(sensitivity.time) / 60,
                    start: sensitivity.time
                )
            }

            if sensitivities.contains(where: { $0.sensitivity <= 0 }) {
                await MainActor.run {
                    nightscoutImportStatus = .failed
                }
                throw NSError(
                    domain: "ImportError",
                    code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid Nightscout insulin sensitivity profile. Import aborted."]
                )
            }

            let sensitivitiesProfile = InsulinSensitivities(
                units: .mgdL,
                userPreferredUnits: .mgdL,
                sensitivities: sensitivities
            )

            // Targets
            let targets = fetchedProfile.target_low.map { target in
                BGTargetEntry(
                    low: shouldConvertToMgdL ? correctUnitParsingOffsets(target.value.asMgdL) : target.value,
                    high: shouldConvertToMgdL ? correctUnitParsingOffsets(target.value.asMgdL) : target.value,
                    start: target.time,
                    offset: offset(target.time) / 60
                )
            }

            let targetsProfile = BGTargets(units: .mgdL, userPreferredUnits: .mgdL, targets: targets)

            // Store therapy settings in-memory in state model for further review
            finalizeImport(
                targets: targetsProfile,
                basals: basals,
                carbRatios: carbratiosProfile,
                sensitivities: sensitivitiesProfile,
                userPreferredUnitsFromImport: fetchedProfile.units,
                currentStep: currentStep
            )
        } catch {
            await MainActor.run {
                self.nightscoutImportErrors.append(error.localizedDescription)
                debug(.service, "Settings import failed with error: \(error.localizedDescription)")
            }
        }
    }

    fileprivate func finalizeImport(
        targets targetsProfile: BGTargets,
        basals: [BasalProfileEntry],
        carbRatios carbratiosProfile: CarbRatios,
        sensitivities sensitivitiesProfile: InsulinSensitivities,
        userPreferredUnitsFromImport: String,
        currentStep: Binding<OnboardingStep>
    ) {
        // Parse: targetsProfile → targetItems
        targetItems = targetsProfile.targets.map { entry in
            let timeIndex = targetTimeValues.firstIndex(where: { Int($0) == entry.offset * 60 }) ?? 0
            let lowIndex = targetRateValues.enumerated().min(by: {
                abs(Double($0.element) - Double(entry.low)) < abs(Double($1.element) - Double(entry.low))
            })?.offset ?? 0

            return TargetsEditor.Item(lowIndex: lowIndex, highIndex: lowIndex, timeIndex: timeIndex)
        }
        initialTargetItems = targetItems

        // Parse: basals → basalProfileItems
        basalProfileItems = basals.map { entry in
            let timeIndex = basalProfileTimeValues.firstIndex(where: { Int($0) == entry.minutes * 60 }) ?? 0
            let rateIndex = basalProfileRateValues.enumerated().min(by: {
                abs(Double($0.element) - Double(entry.rate)) < abs(Double($1.element) - Double(entry.rate))
            })?.offset ?? 0

            return BasalProfileEditor.Item(rateIndex: rateIndex, timeIndex: timeIndex)
        }
        initialBasalProfileItems = basalProfileItems

        // Parse: carbratiosProfile → carbRatioItems
        carbRatioItems = carbratiosProfile.schedule.map { entry in
            let timeIndex = carbRatioTimeValues.firstIndex(where: { Int($0) == entry.offset * 60 }) ?? 0
            let rateIndex = carbRatioRateValues.enumerated().min(by: {
                abs(Double($0.element) - Double(entry.ratio)) < abs(Double($1.element) - Double(entry.ratio))
            })?.offset ?? 0

            return CarbRatioEditor.Item(rateIndex: rateIndex, timeIndex: timeIndex)
        }
        initialCarbRatioItems = carbRatioItems

        // Parse: sensitivitiesProfile → isfItems
        isfItems = sensitivitiesProfile.sensitivities.map { entry in
            let timeIndex = isfTimeValues.firstIndex(where: { Int($0) == entry.offset * 60 }) ?? 0
            let rateIndex = isfRateValues.enumerated().min(by: {
                abs(Double($0.element) - Double(entry.sensitivity)) < abs(Double($1.element) - Double(entry.sensitivity))
            })?.offset ?? 0

            return ISFEditor.Item(rateIndex: rateIndex, timeIndex: timeIndex)
        }
        initialISFItems = isfItems

        units = userPreferredUnitsFromImport.contains("mmol") ? .mmolL : .mgdL

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.nightscoutImportStatus = .finished
            // navigate to the next onboarding step
            if let next = currentStep.wrappedValue.next {
                currentStep.wrappedValue = next
            }
        }
    }

    fileprivate func correctUnitParsingOffsets(_ parsedValue: Decimal) -> Decimal {
        Int(parsedValue) % 2 == 0 ? parsedValue : parsedValue + 1
    }

    fileprivate func offset(_ string: String) -> Int {
        let hours = Int(string.prefix(2)) ?? 0
        let minutes = Int(string.suffix(2)) ?? 0
        return ((hours * 60) + minutes) * 60
    }

    enum ImportStatus {
        case running
        case finished
        case failed
    }
}
