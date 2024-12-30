enum AutosensSettings {
    enum Config {}
}

protocol AutosensSettingsProvider: Provider {
    var autosense: Autosens { get }
}
