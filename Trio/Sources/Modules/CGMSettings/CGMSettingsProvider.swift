extension CGMSettings {
    final class Provider: BaseProvider, CGMSettingsProvider {
        @Injected() var apsManager: APSManager!
    }
}
