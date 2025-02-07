extension AutosensSettings {
    final class Provider: BaseProvider, AutosensSettingsProvider {
        var autosense: Autosens {
            storage.retrieve(OpenAPS.Settings.autosense, as: Autosens.self)
                ?? Autosens(from: OpenAPS.defaults(for: OpenAPS.Settings.autosense))
                ?? Autosens(ratio: 1, newisf: nil, timestamp: nil)
        }
    }
}
