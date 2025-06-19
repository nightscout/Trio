import Foundation

class TimeZoneForTests {
    private var originalTZ: String? = ProcessInfo.processInfo.environment["TZ"]
    private var originalDefaultTimeZone: TimeZone? = TimeZone.current

    // Helper function to set timezone
    func setTimezone(identifier: String) {
        // Set environment variable
        setenv("TZ", identifier, 1)
        tzset() // Make the change take effect

        // Force update the default TimeZone
        // This is the critical missing piece
        if let timeZone = TimeZone(identifier: identifier) {
            TimeZone.ReferenceType.default = timeZone

            // For extra assurance, you can log to verify
            print("Timezone set to: \(TimeZone.current.identifier)")
        } else {
            print("Failed to create TimeZone with identifier: \(identifier)")
        }
    }

    // Helper function to reset timezone
    func resetTimezone() {
        // Restore system timezone from environment
        if let originalTZ = originalTZ {
            setenv("TZ", originalTZ, 1)
        } else {
            unsetenv("TZ")
        }
        tzset()

        // Restore original default TimeZone
        if let originalTimeZone = originalDefaultTimeZone {
            TimeZone.ReferenceType.default = originalTimeZone
        }
    }
}
