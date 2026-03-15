import Foundation

enum ISFTiersEditor {
    enum Config {}
}

protocol ISFTiersEditorProvider: Provider {
    var tiersSettings: InsulinSensitivityTiers { get }
    func saveTiersSettings(_ settings: InsulinSensitivityTiers)
}
