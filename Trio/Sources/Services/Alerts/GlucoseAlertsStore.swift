import Combine
import Foundation

/// Persists the user's `[GlucoseAlert]` list and `GlucoseAlertConfiguration`
/// to `UserDefaults`. SwiftUI views bind to `@Published` properties; mutations
/// flow back to disk on the next runloop.
final class GlucoseAlertsStore: ObservableObject {
    static let shared = GlucoseAlertsStore()

    @Published var alerts: [GlucoseAlert]
    @Published var configuration: GlucoseAlertConfiguration

    private let defaults: UserDefaults
    private let alertsKey: String
    private let configKey: String

    private var subscriptions = Set<AnyCancellable>()

    init(
        defaults: UserDefaults = .standard,
        alertsKey: String = "trio.glucoseAlerts.v1",
        configKey: String = "trio.glucoseAlertConfiguration.v1"
    ) {
        self.defaults = defaults
        self.alertsKey = alertsKey
        self.configKey = configKey
        let loaded = Self.decode([GlucoseAlert].self, from: defaults, key: alertsKey) ?? []
        alerts = loaded.isEmpty ? Self.defaultAlerts() : loaded
        configuration = Self.decode(
            GlucoseAlertConfiguration.self,
            from: defaults,
            key: configKey
        ) ?? GlucoseAlertConfiguration()
        bind()
    }

    /// Seed every glucose alarm enabled. Users running a stock CGM app for
    /// low/high notifications can disable the duplicates per-alarm; the
    /// safer default is to have Trio alert until the user opts out.
    /// `urgentLow` cannot be disabled from the editor regardless — it's the
    /// safety floor — but the stored flag is kept honest so the UI binding
    /// stays simple.
    private static func defaultAlerts() -> [GlucoseAlert] {
        [
            GlucoseAlert(type: .urgentLow),
            GlucoseAlert(type: .low),
            GlucoseAlert(type: .forecastedLow),
            GlucoseAlert(type: .high)
        ]
    }

    private func bind() {
        $alerts
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] value in self?.encode(value, to: self?.alertsKey ?? "") }
            .store(in: &subscriptions)
        $configuration
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] value in self?.encode(value, to: self?.configKey ?? "") }
            .store(in: &subscriptions)
    }

    // MARK: - Mutators

    func add(_ alert: GlucoseAlert) { alerts.append(alert) }

    func update(_ alert: GlucoseAlert) {
        guard let index = alerts.firstIndex(where: { $0.id == alert.id }) else { return }
        alerts[index] = alert
    }

    func remove(_ alert: GlucoseAlert) {
        guard canDelete(alert) else { return }
        alerts.removeAll { $0.id == alert.id }
    }

    /// At least one alarm of each type must remain so the user always has
    /// urgent-low / low / forecasted-low / high coverage available. They can
    /// disable any alarm via its enabled toggle but not delete the last one.
    func canDelete(_ alert: GlucoseAlert) -> Bool {
        alerts.filter { $0.type == alert.type }.count > 1
    }

    // MARK: - Codable helpers

    private static func decode<T: Decodable>(
        _: T.Type,
        from defaults: UserDefaults,
        key: String
    ) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func encode<T: Encodable>(_ value: T, to key: String) {
        guard !key.isEmpty, let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
