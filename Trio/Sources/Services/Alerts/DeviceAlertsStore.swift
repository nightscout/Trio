import Combine
import Foundation

/// Persists three `DeviceAlertSeverityConfig` rows (Critical /
/// Time-Sensitive / Normal) to `UserDefaults`. Every pump / device alarm
/// category maps to one of these tiers via `PumpAlertCategory.defaultSeverity`.
final class DeviceAlertsStore: ObservableObject {
    static let shared = DeviceAlertsStore()

    @Published var configs: [DeviceAlertSeverityConfig]

    private let defaults: UserDefaults
    private let configsKey: String

    private var subscriptions = Set<AnyCancellable>()

    init(
        defaults: UserDefaults = .standard,
        configsKey: String = "trio.deviceAlertSeverityConfigs.v1"
    ) {
        self.defaults = defaults
        self.configsKey = configsKey
        let loaded = Self.decode([DeviceAlertSeverityConfig].self, from: defaults, key: configsKey) ?? []
        var bySeverity = Dictionary(uniqueKeysWithValues: loaded.map { ($0.severity, $0) })
        for severity in DeviceAlertSeverity.allCases where bySeverity[severity] == nil {
            bySeverity[severity] = DeviceAlertSeverityConfig(severity: severity)
        }
        configs = DeviceAlertSeverity.allCases.compactMap { bySeverity[$0] }
        bind()
    }

    private func bind() {
        $configs
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] value in self?.encode(value, to: self?.configsKey ?? "") }
            .store(in: &subscriptions)
    }

    func config(for severity: DeviceAlertSeverity) -> DeviceAlertSeverityConfig? {
        configs.first { $0.severity == severity }
    }

    func update(_ config: DeviceAlertSeverityConfig) {
        guard let index = configs.firstIndex(where: { $0.severity == config.severity }) else { return }
        configs[index] = config
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
