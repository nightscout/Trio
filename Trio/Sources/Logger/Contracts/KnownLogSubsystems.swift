import Foundation

enum KnownLogSubsystems {
    static let all: [String] = [Bundle.main.bundleIdentifier].compactMap { $0 } + [
        "com.loopkit.OmnipodKit",
        "com.randallknutson.OmniBLE",
        "com.loopkit.MinimedKit",
        "com.loopkit.CGMBLEKit",
        "org.loopkit.G7SensorKit",
        "org.loopkit.G7SensorKitUI",
        "org.loopkit.G7SensorPlugin",
        "com.ps2.rileylink",
        "com.loopkit.LibreTransmitter",
        "com.loopkit.libre",
        "com.randallknutson.DanaKit",
        "org.nightscout.MedtrumKit",
        "org.nightscout.EversenseKit",
        "com.bastiaanv.AccuChekKit",
        "org.loopkit.LibreLoop",
        "com.loopkit.ShareClient",
        "org.tidepool.TidepoolService",
        "com.loopkit.LoopKit"
    ]
}
