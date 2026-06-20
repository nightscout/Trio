import Combine
import Foundation
import LoopKit

/// Persists a flat list of `[DeviceAlertSeverityConfig]` to `UserDefaults`.
/// Multiple configs per severity tier are allowed — each with its own
/// `activeOption` so users can vary behavior between day and night.
///
/// Seeds three default configs (one per tier, all `activeOption: .always`)
/// on first launch so every severity has a baseline that always matches.
final class DeviceAlertsStore: ObservableObject {
    static let shared = DeviceAlertsStore()

    @Published var configs: [DeviceAlertSeverityConfig]
    /// Per-tier snooze expirations keyed by `DeviceAlertSeverity.rawValue`.
    @Published var tierSnoozes: [String: Date]

    private let defaults: UserDefaults
    private let configsKey: String
    private let snoozesKey: String

    private var subscriptions = Set<AnyCancellable>()

    init(
        defaults: UserDefaults = .standard,
        configsKey: String = "trio.deviceAlertSeverityConfigs.v1",
        snoozesKey: String = "trio.deviceAlertTierSnoozes.v1"
    ) {
        self.defaults = defaults
        self.configsKey = configsKey
        self.snoozesKey = snoozesKey
        let loaded = Self.decode([DeviceAlertSeverityConfig].self, from: defaults, key: configsKey) ?? []
        var seeded = loaded
        for severity in DeviceAlertSeverity.allCases
            where !seeded.contains(where: { $0.severity == severity && $0.activeOption == .always })
        {
            seeded.append(DeviceAlertSeverityConfig(severity: severity, activeOption: .always))
        }
        configs = Self.sorted(seeded)
        let snoozes = Self.decode([String: Date].self, from: defaults, key: snoozesKey) ?? [:]
        tierSnoozes = snoozes.filter { $0.value > Date() }
        bind()
    }

    // MARK: - Per-tier snooze

    func snoozeTier(_ tier: DeviceAlertSeverity, until: Date) {
        if until > Date() {
            tierSnoozes[tier.rawValue] = until
        } else {
            tierSnoozes.removeValue(forKey: tier.rawValue)
        }
    }

    func isTierSnoozed(_ tier: DeviceAlertSeverity, at date: Date) -> Bool {
        guard let until = tierSnoozes[tier.rawValue] else { return false }
        return until > date
    }

    private func bind() {
        $configs
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] value in self?.encode(value, to: self?.configsKey ?? "") }
            .store(in: &subscriptions)
        $tierSnoozes
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] value in self?.encode(value, to: self?.snoozesKey ?? "") }
            .store(in: &subscriptions)
    }

    // MARK: - Lookup

    /// Find the active config for a severity at the given moment. Considers
    /// only enabled variants; picks the one whose `activeOption` matches the
    /// current day/night window, falling back to the `.always` baseline.
    /// Returns nil if every variant in this severity is disabled — caller
    /// should drop the alarm in that case (user explicitly opted out).
    func config(
        for severity: DeviceAlertSeverity,
        at _: Date,
        isNight: Bool
    ) -> DeviceAlertSeverityConfig? {
        // Critical configs are always considered enabled — the editor hides
        // the Enabled toggle on this tier, but legacy stored data may still
        // carry `isEnabled = false` from a prior install. Honoring that
        // flag here would silence the alarm despite the UI no longer
        // exposing a way to re-enable it.
        let matching = configs.filter { config in
            guard config.severity == severity else { return false }
            return severity == .critical || config.isEnabled
        }
        let windowMatch = matching.first { config in
            switch config.activeOption {
            case .always: return false // .always is the fallback, prefer specific match
            case .day: return !isNight
            case .night: return isNight
            }
        }
        if let windowMatch { return windowMatch }
        return matching.first { $0.activeOption == .always } ?? matching.first
    }

    /// All configs in a single severity tier, sorted by `activeOption`
    /// (Day & Night, Day only, Night only).
    func configs(in severity: DeviceAlertSeverity) -> [DeviceAlertSeverityConfig] {
        configs.filter { $0.severity == severity }
    }

    // MARK: - Mutators

    func add(_ config: DeviceAlertSeverityConfig) {
        configs.append(config)
        configs = Self.sorted(configs)
    }

    func update(_ config: DeviceAlertSeverityConfig) {
        guard let index = configs.firstIndex(where: { $0.id == config.id }) else { return }
        configs[index] = config
        configs = Self.sorted(configs)
    }

    func remove(_ config: DeviceAlertSeverityConfig) {
        guard canDelete(config) else { return }
        configs.removeAll { $0.id == config.id }
    }

    /// At least one `.always` config per severity must remain so every alarm
    /// has a baseline to fall back to. Other variants (.day / .night) can be
    /// freely removed.
    func canDelete(_ config: DeviceAlertSeverityConfig) -> Bool {
        guard config.activeOption == .always else { return true }
        let alwaysCount = configs.filter { $0.severity == config.severity && $0.activeOption == .always }.count
        return alwaysCount > 1
    }

    // MARK: - Sorting + Codable helpers

    private static func sorted(_ list: [DeviceAlertSeverityConfig]) -> [DeviceAlertSeverityConfig] {
        list.sorted { lhs, rhs in
            if lhs.severity != rhs.severity {
                return severityRank(lhs.severity) < severityRank(rhs.severity)
            }
            return activeRank(lhs.activeOption) < activeRank(rhs.activeOption)
        }
    }

    private static func severityRank(_ severity: DeviceAlertSeverity) -> Int {
        switch severity {
        case .critical: return 0
        case .timeSensitive: return 1
        case .normal: return 2
        }
    }

    private static func activeRank(_ option: ActiveOption) -> Int {
        switch option {
        case .always: return 0
        case .day: return 1
        case .night: return 2
        }
    }

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
