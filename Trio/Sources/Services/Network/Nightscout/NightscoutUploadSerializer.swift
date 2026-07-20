import Foundation

/// Nightscout's upload serializer: coalesces and serializes upload runs per
/// `NightscoutUploadPipeline` so no two runs of the same pipeline overlap.
/// See `UploadSerializer` for the behavior and reentrancy rules.
typealias NightscoutUploadSerializer = UploadSerializer<NightscoutUploadPipeline>
