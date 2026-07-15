import Foundation
import HealthKit
import LoopKit
import Swinject
import UIKit

// MARK: - TelemetryClient

/// Opt-out anonymous usage check-in. Sends a small JSON payload to a self-hosted
/// endpoint at most once every 24 hours, plus once after a new build is installed.
/// Enabled by default; users can opt out in Settings → Features → App Diagnostics.
///
/// No health data, credentials, or personally-identifying information is sent.
/// See `buildPayload()` for the exact set of fields and `TelemetryPreviewView`
/// for the in-app inspector that renders the same payload.
final class TelemetryClient: Injectable {
    static let shared = TelemetryClient()

    // MARK: Endpoint configuration

    private static let productionBaseURL: URL? = URL(string: "https://telemetry.triodocs.org")

    // MARK: if you fork Trio and keep telemetry enabled, please change the name here

    // so that we can distinguish forks from mainline Trio builds in our telemetry.
    private static let telemetryAppName: String = "Trio"

    /// Effective base URL: respects the debug override in
    /// `PropertyPersistentFlags.telemetryDebugServerURL`, then falls back to
    /// `productionBaseURL`. Used by both the registration and `/checkin` paths.
    private static var baseURL: URL? {
        if let override = PropertyPersistentFlags.shared.telemetryDebugServerURL?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !override.isEmpty,
            let url = URL(string: override)
        {
            return url
        }
        return productionBaseURL
    }

    private static let weeklyInterval: TimeInterval = 7 * 24 * 60 * 60
    private static let dailyInterval: TimeInterval = 24 * 60 * 60
    private static let maxPayloadBytes = 4096

    private static let buildDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    // MARK: Injected services

    @Injected() private var apsManager: APSManager!
    @Injected() private var fetchGlucoseManager: FetchGlucoseManager!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var tidepoolManager: TidepoolManager!
    @Injected() private var healthKitManager: HealthKitManager!
    @Injected() private var keychain: Keychain!

    private let lock = NSRecursiveLock()
    private var didInjectServices = false
    private var timer: DispatchTimer?

    private init() {}

    private func injectIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !didInjectServices else { return }
        injectServices(TrioApp.resolver)
        didInjectServices = true
    }

    // MARK: - Cold launches

    /// Records a cold launch in a sliding 7-day window of timestamps. The count
    /// of entries in the window ships as `coldLaunches7d` in every ping — a
    /// "how often does iOS recycle this process" signal that is directly
    /// comparable across pings regardless of the cadence between them.
    func recordColdLaunch(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Self.weeklyInterval)
        var recent = PropertyPersistentFlags.shared.telemetryColdLaunchTimes ?? []
        recent.removeAll { $0 < cutoff }
        recent.append(now)
        PropertyPersistentFlags.shared.telemetryColdLaunchTimes = recent
    }

    // MARK: - Install identifier

    /// Stable per-install UUID, generated lazily on first call. IDFV resets if
    /// the user deletes every Trio-team app at once; this survives
    /// independently and is wiped only by deleting Trio itself.
    private func installId() -> String {
        if let existing = PropertyPersistentFlags.shared.telemetryInstallId, !existing.isEmpty {
            return existing
        }
        let new = UUID().uuidString
        PropertyPersistentFlags.shared.telemetryInstallId = new
        return new
    }

    // MARK: - Cadence

    /// True when the running build's commit SHA differs from the SHA recorded
    /// at the last successful send. Used at startup to fire one immediate ping
    /// after an app update — the 24h scheduler can't notice a build change and
    /// would otherwise wait out the previous interval.
    func buildShaChangedSinceLastSend() -> Bool {
        let currentSha = BuildDetails.shared.trioCommitSHA
        return PropertyPersistentFlags.shared.telemetryLastSentSha != currentSha
    }

    /// Arms (or re-arms) the 24h send timer. Idempotent. Bails out without
    /// scheduling if the user has opted out — there's nothing for the timer
    /// to do.
    ///
    /// Best-effort fallback only. GCD timers don't advance while the app is
    /// suspended, so on iOS this effectively means "fires only if the app
    /// stays foregrounded for 24h." The reliable cadence driver is
    /// `checkAndSendIfOverdue()` called on every foreground transition and
    /// cold launch.
    func scheduleRecurring() {
        guard PropertyPersistentFlags.shared.telemetryEnabled != false else {
            return
        }

        lock.lock()
        defer { lock.unlock() }

        if timer == nil {
            let t = DispatchTimer(timeInterval: Self.dailyInterval)
            t.eventHandler = { [weak self] in
                Task.detached { await self?.maybeSend() }
            }
            t.resume()
            timer = t
        }
    }

    /// If telemetry isn't opted out and we haven't successfully sent within
    /// the last 24h (or have never sent), fire a send. Called on foreground
    /// transitions and from the cold-launch path so daily cadence is kept.
    ///
    /// Mirrors the pattern used by LoopFollow's `TaskScheduler.checkTasksNow()`:
    /// wall-clock comparison against `telemetryLastSentAt`, fire-and-forget
    /// if overdue. Safe to call repeatedly — if a send already fired within
    /// the window, this is a no-op.
    func checkAndSendIfOverdue() {
        guard PropertyPersistentFlags.shared.telemetryEnabled != false else {
            return
        }

        let lastSent = PropertyPersistentFlags.shared.telemetryLastSentAt
        let overdue: Bool = {
            guard let lastSent else { return true }
            return Date().timeIntervalSince(lastSent) >= Self.dailyInterval
        }()
        guard overdue else { return }

        Task.detached { await self.maybeSend() }
    }

    /// Single entry point for all sends (scheduler tick, settings opt-in,
    /// startup SHA-change). Gated only on the opt-out flag. *When* to send is
    /// the caller's decision — startup handles the SHA-change shortcut, the
    /// timer handles 24h cadence.
    func maybeSend() async {
        guard PropertyPersistentFlags.shared.telemetryEnabled != false else {
            return
        }
        await send()
    }

    // MARK: - Payload

    /// The exact payload that would be POSTed right now. Pure function: shared
    /// by `send()` and `TelemetryPreviewView`.
    func buildPayload() -> [String: Any] {
        injectIfNeeded()

        let bd = BuildDetails.shared
        let info = Bundle.main.infoDictionary ?? [:]

        var payload: [String: Any] = [:]

        if let v = info["CFBundleShortVersionString"] as? String { payload["appVersion"] = v }
        payload["appName"] = TelemetryClient.telemetryAppName
        // appDevVersion is Trio's 4-component dev counter (e.g. "0.7.0.14") —
        // the most precise build identifier we have. Always emit, even when
        // the Info.plist key is missing, so dashboards can rely on the field.
        payload["appDevVersion"] = Bundle.main.appDevVersion ?? "unknown"
        payload["commitSha"] = bd.trioCommitSHA
        payload["branch"] = bd.trioBranch

        // Date-only (yyyy-MM-dd, UTC) build identifier, parsed from the
        // "Tue May 26 12:34:56 UTC 2025" form added in BuildDetails.plist.
        if let date = bd.buildDate() {
            payload["buildDate"] = Self.buildDateFormatter.string(from: date)
        }

        payload["isTestFlight"] = bd.isTestFlightBuild()

        if let idfv = UIDevice.current.identifierForVendor?.uuidString {
            payload["idfv"] = idfv
        }
        payload["installId"] = installId()

        payload["device"] = Self.hardwareIdentifier()
        payload["platform"] = Self.detectPlatform()
        payload["osVersion"] = UIDevice.current.systemVersion
        payload["locale"] = Locale.current.identifier
        payload["timeZone"] = TimeZone.current.identifier

        // Pump model — omitted entirely when no pump is paired.
        if let pump = apsManager?.pumpManager {
            payload["pumpModel"] = pump.localizedTitle
        }

        // CGM: enum tells us the configured *type*; the live manager (if any)
        // tells us the specific model name. Both are useful — `cgmType`
        // distinguishes Dexcom-via-Nightscout from Dexcom-via-direct, etc.
        let settings = settingsManager?.settings
        payload["cgmType"] = settings?.cgm.rawValue ?? CGMType.none.rawValue
        if let cgm = fetchGlucoseManager?.cgmManager {
            payload["cgmModel"] = cgm.localizedTitle
        }

        // Nightscout: keys present in keychain ⇒ configured. We never include
        // the URL or token themselves.
        let nsUrl = keychain?.getValue(String.self, forKey: NightscoutConfig.Config.urlKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let nsSecret = keychain?.getValue(String.self, forKey: NightscoutConfig.Config.secretKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        payload["nightscoutPaired"] = !nsUrl.isEmpty && !nsSecret.isEmpty

        payload["tidepoolPaired"] = tidepoolManager?.getTidepoolServiceUI() != nil

        // Apple Health: report `enabled = true` as soon as *any* per-type write
        // permission is granted, with the full per-type breakdown in
        // `appleHealthWrites`.
        let appleHealthSampleTypes: [(name: String, type: HKObjectType?)] = [
            ("glucose", AppleHealthConfig.healthBGObject),
            ("insulin", AppleHealthConfig.healthInsulinObject),
            ("carbs", AppleHealthConfig.healthCarbObject),
            ("fat", AppleHealthConfig.healthFatObject),
            ("protein", AppleHealthConfig.healthProteinObject)
        ]
        var writePermissions: [String: Bool] = [:]
        for (name, type) in appleHealthSampleTypes {
            let granted = type.flatMap { healthKitManager?.checkWriteToHealthPermissions(objectTypeToHealthStore: $0) } ?? false
            writePermissions[name] = granted
        }
        payload["appleHealthEnabled"] = writePermissions.values.contains(true)
        if !writePermissions.isEmpty {
            payload["appleHealthWrites"] = writePermissions
        }

        if let settings = settings {
            payload["closedLoop"] = settings.closedLoop
            payload["units"] = settings.units.rawValue
            payload["useLiveActivity"] = settings.useLiveActivity
            payload["useCalendar"] = settings.useCalendar
        }

        payload["coldLaunches7d"] = (PropertyPersistentFlags.shared.telemetryColdLaunchTimes ?? []).count

        // Submodule SHAs — small, useful for tracking which LoopKit / OmnipodKit /
        // etc. revision the user is on. Branch is dropped to keep payload size small.
        let submoduleShas = bd.submodules.mapValues { $0.commitSHA }
        if !submoduleShas.isEmpty {
            payload["submodules"] = submoduleShas
        }

        return payload
    }

    // MARK: - Send

    /// Build payload, attest it via App Attest, POST it, update last-sent state
    /// on 2xx. Fire-and-forget; errors are logged at debug level only.
    ///
    /// Flow:
    /// 1. Skip if `TelemetryAttestor.isSupported == false` (simulator, older
    ///    devices). This is the primary opt-out for unsupported hardware —
    ///    sending without attestation would just bounce off the server.
    /// 2. Skip if the install has been flagged forbidden by a previous 403.
    /// 3. Register if needed (idempotent; first launch + once on retry after
    ///    transient failures).
    /// 4. Serialize the payload. Reject if > 4096 bytes (server-enforced cap).
    /// 5. Ask the attestor for an assertion over `SHA256(payload || challenge)`.
    /// 6. POST `/checkin` with the three App Attest headers.
    ///
    /// Backoff: failures don't update `telemetryLastSentAt`, so the next
    /// scheduler tick / cold launch retries naturally. The 24h cadence is the
    /// natural backoff floor; no per-attempt exponential timer is added.
    func send() async {
        guard let baseURL = Self.baseURL else {
            debug(.telemetry, "skip send: server URL not configured")
            return
        }

        let attestor = TelemetryAttestor.shared
        guard attestor.isSupported else {
            debug(.telemetry, "skip send: App Attest unsupported (simulator or older device)")
            return
        }
        guard !attestor.isForbidden else {
            debug(.telemetry, "skip send: app_id previously rejected (403)")
            return
        }

        do {
            try await attestor.registerIfNeeded(baseURL: baseURL)
        } catch TelemetryAttestor.AttestError.forbidden {
            // Already logged + sticky-flagged in registerIfNeeded.
            return
        } catch {
            debug(.telemetry, "register failed: \(error) — will retry next cycle")
            return
        }

        let payload = buildPayload()
        guard let body = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            debug(.telemetry, "skip send: payload not JSON-serializable")
            return
        }
        guard body.count <= Self.maxPayloadBytes else {
            debug(.telemetry, "skip send: payload exceeds \(Self.maxPayloadBytes) bytes (\(body.count))")
            return
        }

        let assertion: (assertion: String, keyID: String, challenge: String)
        do {
            assertion = try await attestor.assertion(forPayload: body, baseURL: baseURL)
        } catch {
            debug(.telemetry, "assertion failed: \(error)")
            return
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("checkin"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(assertion.keyID, forHTTPHeaderField: "X-AppAttest-KeyId")
        request.setValue(assertion.assertion, forHTTPHeaderField: "X-AppAttest-Assertion")
        request.setValue(assertion.challenge, forHTTPHeaderField: "X-Challenge")
        request.httpBody = body
        request.timeoutInterval = 15

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                debug(.telemetry, "send: non-HTTP response")
                return
            }
            switch http.statusCode {
            case 200 ..< 300:
                PropertyPersistentFlags.shared.telemetryLastSentAt = Date()
                PropertyPersistentFlags.shared.telemetryLastSentSha = BuildDetails.shared.trioCommitSHA
                debug(.telemetry, "send ok status=\(http.statusCode)")
            case 401:
                // Server doesn't recognize our registration (e.g. its registry
                // was wiped). Drop the local keyID + registered flag so the
                // next cycle generates a fresh key and re-attests — `attestKey`
                // can't be re-run on the existing keyID (one-shot per Apple).
                attestor.invalidateRegistration()
                debug(.telemetry, "send 401: stale registration, will re-register next cycle")
            default:
                debug(.telemetry, "send non-2xx status=\(http.statusCode)")
            }
        } catch {
            debug(.telemetry, "send error: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    /// `iPhone15,2`-style identifier from `utsname.machine`. Returns
    /// `Simulator <SIMULATOR_MODEL_IDENTIFIER>` on the simulator so analysis
    /// can ignore those rows.
    static func hardwareIdentifier() -> String {
        #if targetEnvironment(simulator)
            let env = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "Unknown"
            return "Simulator \(env)"
        #else
            var sys = utsname()
            uname(&sys)
            let mirror = Mirror(reflecting: sys.machine)
            let machine = mirror.children.reduce(into: "") { acc, child in
                guard let v = child.value as? Int8, v != 0 else { return }
                acc.append(Character(UnicodeScalar(UInt8(v))))
            }
            return machine.isEmpty ? "Unknown" : machine
        #endif
    }

    static func detectPlatform() -> String {
        #if targetEnvironment(macCatalyst)
            return "macCatalyst"
        #else
            switch UIDevice.current.userInterfaceIdiom {
            case .pad: return "iPadOS"
            default: return "iOS"
            }
        #endif
    }
}
