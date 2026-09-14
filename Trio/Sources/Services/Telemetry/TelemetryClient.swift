import Foundation
import HealthKit
import LoopKit
import Swinject
import UIKit

/// Serializes telemetry eligibility decisions across foreground, timer, and
/// background wake triggers. Actors are reentrant, so `isSending` must remain
/// set while the operation is suspended on network work.
actor TelemetrySendGate {
    // Actor isolation provides the synchronization; an atomic wrapper would
    // be redundant and would not protect the eligibility/send transaction.
    private var isSending = false

    func runIfEligible(
        now: Date,
        lastSentAt: Date?,
        lastAttemptAt: Date?,
        minimumInterval: TimeInterval,
        retryInterval: TimeInterval,
        force: Bool = false,
        operation: () async -> Bool,
        onAttempt: () -> Void = {},
        onSuccess: () -> Void = {}
    ) async -> Bool {
        guard !isSending else { return false }
        guard force || Self.isOverdue(now: now, lastSentAt: lastSentAt, minimumInterval: minimumInterval) else {
            return false
        }
        guard Self.isOverdue(now: now, lastSentAt: lastAttemptAt, minimumInterval: retryInterval) else {
            return false
        }

        isSending = true
        defer { isSending = false }
        onAttempt()
        let succeeded = await operation()
        if succeeded {
            onSuccess()
        }
        return succeeded
    }

    nonisolated static func isOverdue(now: Date, lastSentAt: Date?, minimumInterval: TimeInterval) -> Bool {
        guard let lastSentAt else { return true }
        return now.timeIntervalSince(lastSentAt) >= minimumInterval
    }
}

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

    enum SendReason: String {
        case backgroundActivity = "background_activity"
        case buildChange = "build_change"
        case coldLaunch = "cold_launch"
        case foreground
        case manual
        case optIn = "opt_in"
        case timer
    }

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
    private static let retryInterval: TimeInterval = 60 * 60
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
    private let sendGate = TelemetrySendGate()
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
    /// stays foregrounded for 24h." Daily cadence is instead driven by
    /// overdue checks during cold launch, foreground transitions, and natural
    /// CGM background activity.
    func scheduleRecurring() {
        guard PropertyPersistentFlags.shared.telemetrySharingEnabled != false else {
            return
        }

        lock.lock()
        defer { lock.unlock() }

        if timer == nil {
            let t = DispatchTimer(timeInterval: Self.dailyInterval)
            t.eventHandler = { [weak self] in
                Task.detached { await self?.sendIfOverdue(reason: .timer) }
            }
            t.resume()
            timer = t
        }
    }

    /// Fire-and-forget convenience for synchronous lifecycle callbacks.
    func checkAndSendIfOverdue(reason: SendReason) {
        Task.detached { await self.sendIfOverdue(reason: reason) }
    }

    /// Awaitable daily-cadence entry point. All trigger paths pass through the
    /// actor gate, preventing overlapping requests and enforcing a one-hour
    /// retry delay after an unsuccessful attempt.
    @discardableResult
    func sendIfOverdue(reason: SendReason, now: Date = Date()) async -> Bool {
        guard PropertyPersistentFlags.shared.telemetrySharingEnabled != false else { return false }

        return await sendGate.runIfEligible(
            now: now,
            lastSentAt: PropertyPersistentFlags.shared.telemetryLastSentAt,
            lastAttemptAt: PropertyPersistentFlags.shared.telemetryLastAttemptAt,
            minimumInterval: Self.dailyInterval,
            retryInterval: Self.retryInterval
        ) { [weak self] in
            await self?.send(reason: reason) ?? false
        } onAttempt: {
            PropertyPersistentFlags.shared.telemetryLastAttemptAt = now
        } onSuccess: {
            self.recordSuccessfulSend()
        }
    }

    /// Starts a separate, bounded UIKit background task for an opportunistic
    /// overdue check. This keeps telemetry outside the critical glucose/loop
    /// operation while allowing an already-running app enough time to finish
    /// its daily request before iOS suspends it.
    func checkAndSendIfOverdueInBackground() {
        Task { @MainActor in
            var backgroundTaskID = startBackgroundTask(withName: "Daily Telemetry Check-In")
            await sendIfOverdue(reason: .backgroundActivity)
            endBackgroundTaskSafely(&backgroundTaskID, taskName: "Daily Telemetry Check-In")
        }
    }

    /// Single entry point for all sends (scheduler tick, settings opt-in,
    /// startup SHA-change). Gated only on the opt-out flag. *When* to send is
    /// the caller's decision — startup handles the SHA-change shortcut, the
    /// timer handles 24h cadence.
    func maybeSend(reason: SendReason = .manual) async {
        guard PropertyPersistentFlags.shared.telemetrySharingEnabled != false else {
            return
        }
        await sendGate.runIfEligible(
            now: Date(),
            lastSentAt: PropertyPersistentFlags.shared.telemetryLastSentAt,
            lastAttemptAt: PropertyPersistentFlags.shared.telemetryLastAttemptAt,
            minimumInterval: Self.dailyInterval,
            retryInterval: Self.retryInterval,
            force: true
        ) { [weak self] in
            await self?.send(reason: reason) ?? false
        } onAttempt: {
            PropertyPersistentFlags.shared.telemetryLastAttemptAt = Date()
        } onSuccess: {
            self.recordSuccessfulSend()
        }
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

    private func recordSuccessfulSend() {
        PropertyPersistentFlags.shared.telemetryLastSentAt = Date()
        PropertyPersistentFlags.shared.telemetryLastSentSha = BuildDetails.shared.trioCommitSHA
        PropertyPersistentFlags.shared.telemetryLastAttemptAt = nil
    }

    /// Build payload, attest it via App Attest, and POST it. Returns success on
    /// 2xx so the send gate can update last-sent state; errors are logged at
    /// debug level only.
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
    /// Backoff: failures don't update `telemetryLastSentAt`; the separate
    /// `telemetryLastAttemptAt` gate prevents another attempt for one hour.
    /// Successful sends clear that failure-backoff timestamp and advance the
    /// normal 24-hour cadence.
    @discardableResult
    func send(reason: SendReason) async -> Bool {
        func failed(_ reason: String) -> Bool {
            PropertyPersistentFlags.shared.telemetryLastFailureReason = reason
            return false
        }

        guard let baseURL = Self.baseURL else {
            debug(.telemetry, "skip send: server URL not configured")
            return failed("server_url_not_configured")
        }

        let attestor = TelemetryAttestor.shared
        guard attestor.isSupported else {
            debug(.telemetry, "skip send: App Attest unsupported (simulator or older device)")
            return failed("app_attest_unsupported")
        }
        guard !attestor.isForbidden else {
            debug(.telemetry, "skip send: app_id previously rejected (403)")
            return failed("app_attest_forbidden")
        }

        do {
            try await attestor.registerIfNeeded(baseURL: baseURL)
        } catch TelemetryAttestor.AttestError.forbidden {
            // Already logged + sticky-flagged in registerIfNeeded.
            return failed("registration_forbidden")
        } catch {
            debug(.telemetry, "register failed: \(error) — will retry next cycle")
            return failed("registration_failed")
        }

        let payload = buildPayload()
        guard let body = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            debug(.telemetry, "skip send: payload not JSON-serializable")
            return failed("payload_serialization_failed")
        }
        guard body.count <= Self.maxPayloadBytes else {
            debug(.telemetry, "skip send: payload exceeds \(Self.maxPayloadBytes) bytes (\(body.count))")
            return failed("payload_too_large")
        }

        let assertion: (assertion: String, keyID: String, challenge: String)
        do {
            assertion = try await attestor.assertion(forPayload: body, baseURL: baseURL)
        } catch {
            debug(.telemetry, "assertion failed: \(error)")
            return failed("assertion_failed")
        }

        let previousFailureReason = PropertyPersistentFlags.shared.telemetryLastFailureReason
        guard let checkinURL = Self.checkinURL(
            baseURL: baseURL,
            reason: reason,
            lastFailureReason: previousFailureReason
        ) else {
            return failed("request_url_failed")
        }

        var request = URLRequest(url: checkinURL)
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
                return failed("non_http_response")
            }
            switch http.statusCode {
            case 200 ..< 300:
                PropertyPersistentFlags.shared.telemetryLastFailureReason = nil
                debug(.telemetry, "send ok status=\(http.statusCode)")
                return true
            case 401:
                // Server doesn't recognize our registration (e.g. its registry
                // was wiped). Drop the local keyID + registered flag so the
                // next cycle generates a fresh key and re-attests — `attestKey`
                // can't be re-run on the existing keyID (one-shot per Apple).
                attestor.invalidateRegistration()
                warning(.telemetry, "send 401: stale registration, will re-register next cycle")
                return failed("http_401")
            default:
                warning(.telemetry, "send non-2xx status=\(http.statusCode)")
                return failed("http_\(http.statusCode)")
            }
        } catch {
            warning(.telemetry, "send request failed", error: error)
            return failed("request_failed")
        }
    }

    // MARK: - Helpers

    static func checkinURL(
        baseURL: URL,
        reason: SendReason,
        lastFailureReason: String?
    ) -> URL? {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("checkin"),
            resolvingAgainstBaseURL: false
        ) else { return nil }

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "reason", value: reason.rawValue))
        if let lastFailureReason, !lastFailureReason.isEmpty {
            queryItems.append(URLQueryItem(name: "lastFailureReason", value: lastFailureReason))
        }
        components.queryItems = queryItems
        return components.url
    }

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
