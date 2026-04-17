import SwiftUI

extension BolusCalculatorConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Published var units: GlucoseUnits = .mgdL
        @Published var overrideFactor: Decimal = 0
        @Published var fattyMeals: Bool = false
        @Published var fattyMealFactor: Decimal = 0
        @Published var sweetMeals: Bool = false
        @Published var sweetMealFactor: Decimal = 0
        @Published var displayPresets: Bool = true
        @Published var confirmBolusWhenVeryLowGlucose: Bool = false
        @Published var barcodeScannerEnabled: Bool = false
        @Published var barcodeScannerOnlyCarbs: Bool = false
        @Published var openFoodFactsUsername: String = ""
        @Published var openFoodFactsPassword: String = ""
        @Published var isOpenFoodFactsLoginSuccessful: Bool = false
        @Published var isOpenFoodFactsLoginInProgress: Bool = false
        @Published var openFoodFactsLoginError: String?

        private let openFoodFactsClient = BarcodeScanner.OpenFoodFactsClient()

        func loginToOpenFoodFacts() {
            let trimmedUsername = openFoodFactsUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedUsername.isEmpty, !openFoodFactsPassword.isEmpty else {
                isOpenFoodFactsLoginSuccessful = false
                openFoodFactsLoginError = String(localized: "Please enter username and password.")
                return
            }

            isOpenFoodFactsLoginInProgress = true
            openFoodFactsLoginError = nil

            Task { @MainActor in
                await openFoodFactsClient.setCredentials(username: trimmedUsername, password: openFoodFactsPassword)

                do {
                    let loginSuccessful = try await openFoodFactsClient.login()
                    isOpenFoodFactsLoginSuccessful = loginSuccessful
                    if !loginSuccessful {
                        openFoodFactsLoginError = String(localized: "Login failed. Check username/password.")
                    }
                } catch {
                    isOpenFoodFactsLoginSuccessful = false
                    openFoodFactsLoginError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }

                isOpenFoodFactsLoginInProgress = false
            }
        }

        override func subscribe() {
            units = settingsManager.settings.units

            subscribeSetting(\.overrideFactor, on: $overrideFactor) { overrideFactor = $0 }
            subscribeSetting(\.fattyMeals, on: $fattyMeals) { fattyMeals = $0 }
            subscribeSetting(\.displayPresets, on: $displayPresets) { displayPresets = $0 }
            subscribeSetting(\.fattyMealFactor, on: $fattyMealFactor) { fattyMealFactor = $0 }
            subscribeSetting(\.sweetMeals, on: $sweetMeals) { sweetMeals = $0 }
            subscribeSetting(\.sweetMealFactor, on: $sweetMealFactor) { sweetMealFactor = $0 }
            subscribeSetting(\.confirmBolus, on: $confirmBolusWhenVeryLowGlucose) { confirmBolusWhenVeryLowGlucose = $0 }
            subscribeSetting(\.barcodeScannerEnabled, on: $barcodeScannerEnabled) {
                barcodeScannerEnabled = $0 }
            subscribeSetting(\.barcodeScannerOnlyCarbs, on: $barcodeScannerOnlyCarbs) {
                barcodeScannerOnlyCarbs = $0 }
            subscribeSetting(\.openFoodFactsUsername, on: $openFoodFactsUsername) {
                openFoodFactsUsername = $0
            }
            subscribeSetting(\.openFoodFactsPassword, on: $openFoodFactsPassword) {
                openFoodFactsPassword = $0
            }

            Task { @MainActor in
                await self.openFoodFactsClient.setCredentials(
                    username: self.openFoodFactsUsername,
                    password: self.openFoodFactsPassword
                )
                self.isOpenFoodFactsLoginSuccessful = await self.openFoodFactsClient.hasValidSessionCookie()
            }
        }
    }
}

extension BolusCalculatorConfig.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}
