import Foundation

enum AutoApplyOverride {
    enum DataFlow {}
}

protocol AutoApplyOverrideProvider: Provider {
    func getOverridePresets() -> [OverrideStored]
    func getActivityLog() -> [ActivityLogEntry]
    func clearActivityLog()
}
