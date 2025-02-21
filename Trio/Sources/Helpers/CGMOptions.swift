let cgmOptions: [CGMOption] = [
    CGMOption(name: "Dexcom G5", predicate: { $0.type == .plugin && $0.displayName.contains("G5") }),
    CGMOption(name: "Dexcom G6 / ONE", predicate: { $0.type == .plugin && $0.displayName.contains("G6") }),
    CGMOption(name: "Dexcom G7 / ONE+", predicate: { $0.type == .plugin && $0.displayName.contains("G7") }),
    CGMOption(name: "Dexcom Share", predicate: { $0.type == .plugin && $0.displayName.contains("Dexcom Share") }),
    CGMOption(name: "FreeStyle Libre", predicate: { $0.type == .plugin && $0.displayName == "FreeStyle Libre" }),
    CGMOption(
        name: "FreeStyle Libre Demo",
        predicate: { $0.type == .plugin && $0.displayName == "FreeStyle Libre Demo" }
    ),
    CGMOption(name: "Glucose Simulator", predicate: { $0.type == .simulator }),
    CGMOption(name: "Medtronic Enlite", predicate: { $0.type == .enlite }),
    CGMOption(name: "Nightscout as CGM", predicate: { $0.type == .nightscout }),
    CGMOption(name: "xDrip4iOS", predicate: { $0.type == .xdrip })
]
