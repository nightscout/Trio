import Foundation
import LoopKit
import Swinject

/// Listens to `DeterminationObserver` and issues `glucose.forecastedLow` when
/// the blended +20-min prediction (see `ForecastedGlucoseEvaluator`) drops
/// below the user's low-glucose threshold. Retracts once the forecast
/// recovers above the threshold plus a small margin to avoid flap.
final class ForecastedGlucoseAlertObserver: Injectable {
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var trioAlertManager: TrioAlertManager!
    @Injected() private var settingsManager: SettingsManager!

    private static let recoveryMarginMgDL: Decimal = 10
    private static let alertIdentifier = "glucose.forecastedLow"

    private let queue = DispatchQueue(label: "ForecastedGlucoseAlertObserver.queue")
    private var isFiring = false

    init(resolver: Resolver) {
        injectServices(resolver)
        broadcaster.register(DeterminationObserver.self, observer: self)
    }

    private var alertID: Alert.Identifier {
        Alert.Identifier(
            managerIdentifier: BaseTrioAlertManager.managerIdentifier,
            alertIdentifier: Self.alertIdentifier
        )
    }
}

extension ForecastedGlucoseAlertObserver: DeterminationObserver {
    func determinationDidUpdate(_ determination: Determination) {
        guard let result = ForecastedGlucoseEvaluator.evaluate(determination: determination) else {
            return
        }
        let threshold = settingsManager.settings.lowGlucose
        let predicted = result.predictedGlucose
        let units = settingsManager.settings.units

        queue.async { [weak self] in
            guard let self else { return }
            let firing = self.isFiring

            if predicted < threshold, !firing {
                self.isFiring = true
                let title = String(localized: "Predicted Low")
                let body = String(
                    format: String(
                        localized: "Glucose forecasted to reach %1$@ within %2$d minutes (limit: %3$@)."
                    ),
                    predicted.formatted(withUnits: units),
                    result.horizonMinutes,
                    threshold.formatted(withUnits: units)
                )
                let content = Alert.Content(
                    title: title,
                    body: body,
                    acknowledgeActionButtonLabel: String(localized: "OK")
                )
                let alert = Alert(
                    identifier: self.alertID,
                    foregroundContent: content,
                    backgroundContent: content,
                    trigger: .immediate,
                    interruptionLevel: TrioAlertCategory.glucoseForecastedLow.interruptionLevel,
                    sound: .sound(name: "trill.caf")
                )
                self.trioAlertManager.issueAlert(alert)
            } else if firing, predicted >= threshold + Self.recoveryMarginMgDL {
                self.isFiring = false
                self.trioAlertManager.retractAlert(identifier: self.alertID)
            }
        }
    }
}
