extension Settings {
    final class Provider: BaseProvider, SettingsProvider {
        @Injected() var tidePoolManager: TidePoolManager!
    }
}
