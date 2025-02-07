extension CGM {
    final class Provider: BaseProvider, CGMProvider {
        @Injected() var apsManager: APSManager!
    }
}
