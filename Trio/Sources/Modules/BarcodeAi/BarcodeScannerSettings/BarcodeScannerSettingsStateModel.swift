import Foundation
import Observation
import SwiftUI

extension BarcodeScannerSettings {
    @Observable final class StateModel: BaseStateModel<Provider> {
        // MARK: - Published Properties

        var useAINutritionScanner: Bool = false
        var modelManager: BarcodeScanner.NutritionModelManager { BarcodeScanner.NutritionModelManager.shared }

        // MARK: - Lifecycle

        override func subscribe() {
            useAINutritionScanner = settingsManager.settings.useAINutritionScanner
        }

        // MARK: - Actions

        func updateAINutritionScannerSetting(_ enabled: Bool) {
            settingsManager.settings.useAINutritionScanner = enabled
        }

        func checkModelStatus() {
            modelManager.checkModelStatus()
        }

        func downloadModel(from url: String) async {
            await modelManager.downloadModel(from: url)
            if case .downloaded = modelManager.state {
                try? await modelManager.loadModel()
            }
        }

        func loadModel() async {
            try? await modelManager.loadModel()
        }

        func deleteModel() {
            modelManager.deleteModel()
        }

        func cancelDownload() {
            modelManager.cancelDownload()
        }
    }
}
