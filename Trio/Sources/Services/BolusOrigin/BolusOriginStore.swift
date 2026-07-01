import Foundation
import Swinject

/// Tracks where in-flight boluses came from, keyed by the opaque reference passed to the pump.
///
/// When the delivered dose is reported back with the same reference echoed on `DoseEntry.bolusReference`,
/// the origin can be resolved and recorded. The mapping is persisted so it survives an app restart during
/// the in-flight window, matching the pump-side persistence of the reference.
protocol BolusOriginStore {
    /// Remember an origin under a freshly generated reference and return the reference to pass to the pump.
    func makeReference(for origin: BolusOrigin) -> UUID
    /// Resolve the origin previously stored for a reference, if any.
    func origin(for reference: UUID) -> BolusOrigin?
    /// Drop the mapping once it has been consumed.
    func remove(_ reference: UUID)
}

private struct BolusOriginEntry: JSON, Equatable {
    let reference: UUID
    let origin: BolusOrigin
    let createdAt: Date
}

final class BaseBolusOriginStore: BolusOriginStore, Injectable {
    @Injected() private var storage: FileStorage!

    private let lock = NSRecursiveLock()
    private var entries: [BolusOriginEntry] = []

    /// In-flight references are short-lived; drop anything older than this so the file stays bounded.
    private static let maxAge: TimeInterval = 6 * 60 * 60
    private static let fileName = "bolus_origins.json"

    init(resolver: Resolver) {
        injectServices(resolver)
        sync {
            entries = (storage.retrieve(Self.fileName, as: [BolusOriginEntry].self) ?? [])
                .filter { $0.createdAt > Date().addingTimeInterval(-Self.maxAge) }
        }
    }

    func makeReference(for origin: BolusOrigin) -> UUID {
        let reference = UUID()
        register(origin, for: reference)
        return reference
    }

    private func register(_ origin: BolusOrigin, for reference: UUID) {
        sync {
            entries.removeAll { $0.reference == reference }
            entries.append(BolusOriginEntry(reference: reference, origin: origin, createdAt: Date()))
            persist()
        }
    }

    func origin(for reference: UUID) -> BolusOrigin? {
        sync { entries.first(where: { $0.reference == reference })?.origin }
    }

    func remove(_ reference: UUID) {
        sync {
            entries.removeAll { $0.reference == reference }
            persist()
        }
    }

    // MARK: - Helpers

    @discardableResult private func sync<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    /// Caller must hold `lock`.
    private func persist() {
        let cutoff = Date().addingTimeInterval(-Self.maxAge)
        entries.removeAll { $0.createdAt <= cutoff }
        storage.save(entries, as: Self.fileName)
    }
}
