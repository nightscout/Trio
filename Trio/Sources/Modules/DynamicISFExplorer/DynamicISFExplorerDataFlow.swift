import Foundation

enum DynamicISFExplorer {
    enum Config {}
}

protocol DynamicISFExplorerProvider: Provider {
    /// Scheduled insulin sensitivity in mg/dL/U at the given time.
    func sensitivity(at date: Date) -> Decimal?
    /// Scheduled glucose target in mg/dL at the given time, ignoring temp targets.
    func target(at date: Date) -> Decimal?
    /// TDD averages and override state from the last loop.
    var orefVariables: TrioCustomOrefVariables? { get }
}
