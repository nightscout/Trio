import Combine
import CoreData
import Foundation
import Swinject

protocol OpenSourceClinicManager {
    func syncAll() async
    func uploadGlucose() async
    func uploadPreferences() async
    func uploadTherapyProfile() async
    func testConnection() async throws
    var isEnabled: Bool { get }
    var lastSyncDate: Date? { get }
}

final class BaseOpenSourceClinicManager: OpenSourceClinicManager, Injectable {
    @Injected() private var keychain: Keychain!
    @Injected() private var storage: FileStorage!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var broadcaster: Broadcaster!

    private let api = OpenSourceClinicAPI()
    private var backgroundContext = CoreDataStack.shared.newTaskContext()

    var lastSyncDate: Date?

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: OpenSourceClinicConfig.Keys.isEnabled) && !token.isEmpty
    }

    private var baseURL: URL {
        let urlString = UserDefaults.standard.string(forKey: OpenSourceClinicConfig.Keys.url)
            ?? OpenSourceClinicConfig.Defaults.url
        return URL(string: urlString) ?? URL(string: OpenSourceClinicConfig.Defaults.url)!
    }

    private var token: String {
        if case .success(let value) = keychain.getValue(String.self, forKey: OpenSourceClinicConfig.Keys.token) {
            return value ?? ""
        }
        return ""
    }

    // MARK: - Full Sync

    func syncAll() async {
        guard isEnabled else { return }

        do {
            let payload = try await buildSyncPayload()
            try await api.sync(baseURL: baseURL, token: token, payload: payload)
            lastSyncDate = Date()
        } catch {
            print("[OpenSourceClinic] Sync failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Glucose

    func uploadGlucose() async {
        guard isEnabled else { return }

        do {
            let glucoseEntries = try await fetchRecentGlucose()
            guard !glucoseEntries.isEmpty else { return }

            let units = settingsManager.settings.units == .mgdL ? "mg/dL" : "mmol/L"
            let entries = glucoseEntries.map { entry -> GlucoseEntry in
                let value: Decimal = settingsManager.settings.units == .mmolL
                    ? (entry.sgv ?? 0).asMmolL
                    : Decimal(entry.sgv ?? 0)
                return GlucoseEntry(
                    date: entry.dateString.timeIntervalSince1970 * 1000,
                    value: value,
                    direction: entry.direction?.rawValue ?? "None"
                )
            }

            try await api.uploadGlucose(baseURL: baseURL, token: token, units: units, entries: entries)
        } catch {
            print("[OpenSourceClinic] Glucose upload failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Preferences

    func uploadPreferences() async {
        guard isEnabled else { return }

        let preferences = settingsManager.preferences
        do {
            try await api.uploadPreferences(baseURL: baseURL, token: token, preferences: preferences)
        } catch {
            print("[OpenSourceClinic] Preferences upload failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Therapy Profile

    func uploadTherapyProfile() async {
        guard isEnabled else { return }

        let profile = buildTherapyProfilePayload()
        do {
            try await api.uploadTherapyProfile(baseURL: baseURL, token: token, profile: profile)
        } catch {
            print("[OpenSourceClinic] Therapy profile upload failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Test Connection

    func testConnection() async throws {
        let testURL = baseURL.appendingPathComponent("/v1/trio/sync")
        var request = URLRequest(url: testURL)
        request.httpMethod = "GET"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 401 || httpResponse.statusCode == 200 else {
            throw OpenSourceClinicAPI.APIError.badStatusCode(
                (response as? HTTPURLResponse)?.statusCode ?? -1
            )
        }
    }

    // MARK: - Data Fetching

    private func fetchRecentGlucose() async throws -> [BloodGlucose] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: backgroundContext,
            predicate: NSPredicate(format: "date > %@", Calendar.current.date(byAdding: .hour, value: -24, to: Date())! as NSDate),
            key: "date",
            ascending: false
        )

        return try await backgroundContext.perform {
            guard let fetchedResults = results as? [GlucoseStored] else {
                return []
            }

            return fetchedResults.map { result in
                BloodGlucose(
                    id: result.id?.uuidString ?? UUID().uuidString,
                    sgv: Int(result.glucose),
                    direction: BloodGlucose.Direction(from: result.direction ?? ""),
                    date: Decimal(result.date?.timeIntervalSince1970 ?? Date().timeIntervalSince1970) * 1000,
                    dateString: result.date ?? Date(),
                    unfiltered: Decimal(result.glucose),
                    filtered: Decimal(result.glucose),
                    noise: nil,
                    glucose: Int(result.glucose),
                    type: "sgv"
                )
            }
        }
    }

    // MARK: - Payload Builders

    private func buildSyncPayload() async throws -> TrioSyncPayload {
        let glucoseEntries = try await fetchRecentGlucose()
        let units = settingsManager.settings.units == .mgdL ? "mg/dL" : "mmol/L"

        let glucose = GlucosePayload(
            units: units,
            entries: glucoseEntries.map { entry in
                let value: Decimal = settingsManager.settings.units == .mmolL
                    ? (entry.sgv ?? 0).asMmolL
                    : Decimal(entry.sgv ?? 0)
                return GlucoseEntry(
                    date: entry.dateString.timeIntervalSince1970 * 1000,
                    value: value,
                    direction: entry.direction?.rawValue ?? "None"
                )
            }
        )

        let profile = buildTherapyProfilePayload()
        let preferences = settingsManager.preferences

        let deviceInfo = DeviceInfo(
            app: "trio",
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            os: "ios",
            osVersion: UIDevice.current.systemVersion
        )

        return TrioSyncPayload(
            device: deviceInfo,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            glucose: glucose,
            therapyProfile: profile,
            preferences: preferences,
            treatments: nil,
            deviceStatus: nil,
            autotune: nil
        )
    }

    private func buildTherapyProfilePayload() -> TherapyProfilePayload {
        let basal = storage.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self) ?? []
        let isf = storage.retrieve(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self)
        let cr = storage.retrieve(OpenAPS.Settings.carbRatios, as: CarbRatios.self)
        let targets = storage.retrieve(OpenAPS.Settings.bgTargets, as: BGTargets.self)
        let pump = storage.retrieve(OpenAPS.Settings.settings, as: PumpSettings.self)

        return TherapyProfilePayload(
            dia: pump?.insulinActionCurve ?? 4,
            basal: basal.map { TimeRate(time: $0.start, rate: $0.rate) },
            isf: isf?.sensitivities.map { TimeValue(time: $0.start, value: $0.sensitivity) } ?? [],
            carbRatio: cr?.schedule.map { TimeValue(time: $0.start, value: $0.ratio) } ?? [],
            targets: targets?.targets.map { TimeTarget(time: $0.start, low: $0.low, high: $0.high) } ?? [],
            maxBolus: pump?.maxBolus ?? 10,
            maxBasal: pump?.maxBasal ?? 3
        )
    }
}
