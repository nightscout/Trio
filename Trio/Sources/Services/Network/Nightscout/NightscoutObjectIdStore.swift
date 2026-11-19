import Foundation

/// Nightscout `_id` per local treatment id for one Nightscout site, kept for `retention` after it was recorded.
///
/// Keys are local ids as uploaded in the treatment's `id` field: a pump event id, a carb entry id,
/// or the `fpuID` shared by a meal's carb equivalents. Several `_id`s for one key keep the newest.
struct NightscoutObjectIdCache: Codable, Equatable {
    static let retention: TimeInterval = 24 * 60 * 60

    struct Entry: Codable, Equatable {
        let objectId: String
        let recordedAt: Date
    }

    private(set) var siteURL: String?
    /// When recording started for this site: when the cache for it was created.
    private(set) var firstRecordedAt: Date?
    private(set) var entries: [String: Entry] = [:]

    init(siteURL: String? = nil, createdAt: Date? = nil) {
        self.siteURL = siteURL
        firstRecordedAt = createdAt
    }

    func objectId(forLocalId localId: String) -> String? {
        entries[localId.lowercased()]?.objectId
    }

    /// Starts an empty cache created at `date` when `siteURL` differs from the site the cache belongs to, and sets
    /// the recording start to `date` when it has none. Returns whether the cache changed.
    @discardableResult mutating func switchSite(to siteURL: String?, at date: Date) -> Bool {
        if siteURL != self.siteURL {
            self = NightscoutObjectIdCache(siteURL: siteURL, createdAt: date)
            return true
        }
        guard firstRecordedAt == nil else { return false }
        firstRecordedAt = date
        return true
    }

    mutating func record(localId: String, objectId: String, at date: Date) {
        guard let newId = NightscoutObjectId(objectId) else { return }
        let key = localId.lowercased()
        if let existing = NightscoutObjectId(entries[key]?.objectId), existing > newId {
            return
        }
        entries[key] = Entry(objectId: newId.value, recordedAt: date)
    }

    mutating func purge(now: Date) {
        entries = entries.filter { now.timeIntervalSince($0.value.recordedAt) < Self.retention }
    }

    /// Pairs of echoed `id` and `_id` from a Nightscout treatments POST response, limited to `localIds`.
    /// Objects missing either are skipped.
    static func mappings(fromUploadResponse data: Data, localIds: Set<String>) -> [(localId: String, objectId: String)] {
        guard let objects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return objects.compactMap { object in
            guard let localId = object["id"] as? String, localIds.contains(localId),
                  let objectId = object["_id"] as? String
            else { return nil }
            return (localId, objectId)
        }
    }

    static func normalizedSiteURL(_ url: String?) -> String? {
        guard var url = url?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !url.isEmpty else { return nil }
        while url.hasSuffix("/") {
            url.removeLast()
        }
        return url
    }
}

/// Persists the `_id` cache of the configured Nightscout site; a different site URL starts an empty cache.
final class NightscoutObjectIdStore {
    static let shared = NightscoutObjectIdStore()

    private let lock = NSLock()
    private let configuredSiteURL: () -> String?
    @Persisted private var cache: NightscoutObjectIdCache

    convenience init() {
        let keychain = BaseKeychain()
        self.init(storage: UserDefaults.standard) {
            keychain.getValue(String.self, forKey: NightscoutConfig.Config.urlKey)
        }
    }

    init(storage: KeyValueStorage, configuredSiteURL: @escaping () -> String?) {
        self.configuredSiteURL = configuredSiteURL
        _cache = Persisted(wrappedValue: NightscoutObjectIdCache(), key: "NightscoutObjectIdStore.cache", storage: storage)
    }

    private var currentSiteURL: String? {
        NightscoutObjectIdCache.normalizedSiteURL(configuredSiteURL())
    }

    /// Records `mappings` obtained from a request made against `siteURL`.
    /// Mappings for any site other than the configured one are ignored.
    func record(_ mappings: [(localId: String, objectId: String)], fromSite siteURL: String?, at date: Date = Date()) {
        guard !mappings.isEmpty else { return }
        let currentSiteURL = self.currentSiteURL
        guard let currentSiteURL, NightscoutObjectIdCache.normalizedSiteURL(siteURL) == currentSiteURL else { return }
        lock.lock()
        defer { lock.unlock() }
        var updated = cache
        updated.switchSite(to: currentSiteURL, at: date)
        updated.purge(now: date)
        for mapping in mappings {
            updated.record(localId: mapping.localId, objectId: mapping.objectId, at: date)
        }
        cache = updated
    }

    /// Upper bound on Nightscout lookups after one upload.
    static let maxLookupsPerUpload = 10

    /// Looks up, on `siteURL`, the `_id` of uploaded treatments whose upload response had none, at most
    /// `maxLookupsPerUpload` of them, and records what it finds while `siteURL` is the configured site.
    func resolveMissing(
        localIds: [String],
        fromSite siteURL: String?,
        lookup: (String) async throws -> String?
    ) async {
        let cache = snapshot()
        guard let siteURL, NightscoutObjectIdCache.normalizedSiteURL(siteURL) == cache.siteURL else { return }
        var seen = Set<String>()
        let missing = localIds.filter { localId in
            seen.insert(localId.lowercased()).inserted && NightscoutObjectId(cache.objectId(forLocalId: localId)) == nil
        }
        for localId in missing.prefix(Self.maxLookupsPerUpload) {
            do {
                if let objectId = try await lookup(localId) {
                    record([(localId, objectId)], fromSite: siteURL)
                }
            } catch {
                warning(.nightscout, "Nightscout _id lookup failed", error: error)
            }
        }
    }

    /// The cache for the configured site, created and persisted at `date` when there is none yet.
    @discardableResult func snapshot(at date: Date = Date()) -> NightscoutObjectIdCache {
        let siteURL = currentSiteURL
        lock.lock()
        defer { lock.unlock() }
        var current = cache
        if current.switchSite(to: siteURL, at: date) {
            cache = current
        }
        return current
    }
}
