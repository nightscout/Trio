import Foundation

/// Logical upload “paths” handled by NightscoutManager.
/// Each upload pipeline has its own throttled queue so we don’t double-upload
/// when multiple sources trigger the same work close together.
public enum NightscoutUploadPipeline: String, CaseIterable {
    case carbs
    case pumpHistory
    case overrides
    case tempTargets
    case glucose
    case manualGlucose
    case deviceStatus
}

/// Keys used in Nightscout upload notifications.
public enum NightscoutNotificationKey {
    /// Array of upload pipeline rawValues to upload, e.g. ["carbs", "pumpHistory"].
    public static let uploadPipelines = "uploadPipelines"
    /// Optional string that says who asked for the upload (debug/diagnostics).
    public static let source = "source"
}

public extension Foundation.Notification.Name {
    /// Post this to request one or more uploads by upload pipeline.
    static let nightscoutUploadRequested = Notification.Name("nightscoutUploadRequested")
    /// Posted after we enqueue all requested upload pipelines (not a network completion).
    static let nightscoutUploadDidFinish = Notification.Name("nightscoutUploadDidFinish")
}

/// Convenience helper any component (e.g. APSManager) can call to
/// request uploads. The work is enqueued and deduped per upload pipeline via throttle,
/// so rapid duplicate calls won’t double-upload.
///
/// - Parameters:
///   - uploadPipelines: Which pipelines to request (carbs, pumpHistory, etc).
///   - source: Optional tag for debugging (e.g. "APSManager").
public func requestNightscoutUpload(_ uploadPipelines: [NightscoutUploadPipeline], source: String? = nil) {
    var userInfo: [AnyHashable: Any] = [NightscoutNotificationKey.uploadPipelines: uploadPipelines.map(\.rawValue)]
    if let source { userInfo[NightscoutNotificationKey.source] = source }
    Foundation.NotificationCenter.default.post(name: .nightscoutUploadRequested, object: nil, userInfo: userInfo)
}
