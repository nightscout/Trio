enum Calibrations {
    enum Config {}

    struct Item: Hashable, Identifiable {
        let calibration: Calibration

        var id: String {
            calibration.id.uuidString
        }
    }
}

protocol CalibrationsProvider {}
