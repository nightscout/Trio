import Foundation

protocol FileStorage {
    func save<Value: JSON>(_ value: Value, as name: String)
    func saveAsync<Value: JSON>(_ value: Value, as name: String) async
    func retrieve<Value: JSON>(_ name: String, as type: Value.Type) -> Value?
    func retrieveAsync<Value: JSON>(_ name: String, as type: Value.Type) async -> Value?
    func retrieveRaw(_ name: String) -> RawJSON?
    func retrieveRawAsync(_ name: String) async -> RawJSON?
    func append<Value: JSON>(_ newValue: Value, to name: String)
    func append<Value: JSON>(_ newValues: [Value], to name: String)
    func append<Value: JSON, T: Equatable>(_ newValue: Value, to name: String, uniqBy keyPath: KeyPath<Value, T>)
    func append<Value: JSON, T: Equatable>(_ newValues: [Value], to name: String, uniqBy keyPath: KeyPath<Value, T>)
    func remove(_ name: String)
    func rename(_ name: String, to newName: String)
    func transaction(_ exec: (FileStorage) -> Void)
    func urlFor(file: String) -> URL?
    func parseOnFileSettingsToMgdL() -> Bool
}

final class BaseFileStorage: FileStorage {
    private let processQueue = DispatchQueue.markedQueue(label: "BaseFileStorage.processQueue", qos: .utility)

    func save<Value: JSON>(_ value: Value, as name: String) {
        processQueue.safeSync {
            do {
                if let value = value as? RawJSON, let data = value.data(using: .utf8) {
                    try Disk.save(data, to: .documents, as: name)
                } else {
                    try Disk.save(value, to: .documents, as: name, encoder: JSONCoding.encoder)
                }
            } catch {
                debug(.storage, "Failed to save file '\(name)': \(error)")
            }
        }
    }

    func saveAsync<Value: JSON>(_ value: Value, as name: String) async {
        await withCheckedContinuation { continuation in
            processQueue.safeSync {
                do {
                    if let value = value as? RawJSON, let data = value.data(using: .utf8) {
                        try Disk.save(data, to: .documents, as: name)
                    } else {
                        try Disk.save(value, to: .documents, as: name, encoder: JSONCoding.encoder)
                    }
                } catch {
                    debug(.storage, "Failed to save file '\(name)': \(error)")
                }
                continuation.resume()
            }
        }
    }

    func retrieve<Value: JSON>(_ name: String, as type: Value.Type) -> Value? {
        processQueue.safeSync {
            do {
                return try Disk.retrieve(name, from: .documents, as: type, decoder: JSONCoding.decoder)
            } catch {
                debug(.storage, "Failed to retrieve file '\(name)': \(error)")
                return nil
            }
        }
    }

    func retrieveAsync<Value: JSON>(_ name: String, as type: Value.Type) async -> Value? {
        await withCheckedContinuation { continuation in
            processQueue.safeSync {
                do {
                    let result = try Disk.retrieve(name, from: .documents, as: type, decoder: JSONCoding.decoder)
                    continuation.resume(returning: result)
                } catch {
                    debug(.storage, "Failed to retrieve file '\(name)': \(error)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func retrieveRaw(_ name: String) -> RawJSON? {
        processQueue.safeSync {
            do {
                let data = try Disk.retrieve(name, from: .documents, as: Data.self)
                guard let string = String(data: data, encoding: .utf8) else {
                    debug(.storage, "Failed to decode data as UTF-8 string for file '\(name)'")
                    return nil
                }
                return string
            } catch {
                debug(.storage, "Failed to retrieve file '\(name)': \(error)")
                return nil
            }
        }
    }

    func retrieveRawAsync(_ name: String) async -> RawJSON? {
        await withCheckedContinuation { continuation in
            processQueue.safeSync {
                do {
                    let data = try Disk.retrieve(name, from: .documents, as: Data.self)
                    guard let string = String(data: data, encoding: .utf8) else {
                        debug(.storage, "Failed to decode data as UTF-8 string for file '\(name)'")
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: string)
                } catch {
                    debug(.storage, "Failed to retrieve file '\(name)': \(error)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func append<Value: JSON>(_ newValue: Value, to name: String) {
        processQueue.safeSync {
            do {
                try Disk.append(newValue, to: name, in: .documents, decoder: JSONCoding.decoder, encoder: JSONCoding.encoder)
            } catch {
                debug(.storage, "Failed to append to file '\(name)': \(error)")
            }
        }
    }

    func append<Value: JSON>(_ newValues: [Value], to name: String) {
        processQueue.safeSync {
            do {
                try Disk.append(newValues, to: name, in: .documents, decoder: JSONCoding.decoder, encoder: JSONCoding.encoder)
            } catch {
                debug(.storage, "Failed to append to file '\(name)': \(error)")
            }
        }
    }

    func append<Value: JSON, T: Equatable>(_ newValue: Value, to name: String, uniqBy keyPath: KeyPath<Value, T>) {
        if let value = retrieve(name, as: Value.self) {
            if value[keyPath: keyPath] != newValue[keyPath: keyPath] {
                append(newValue, to: name)
            }
        } else if let values = retrieve(name, as: [Value].self) {
            guard values.first(where: { $0[keyPath: keyPath] == newValue[keyPath: keyPath] }) == nil else {
                return
            }
            append(newValue, to: name)
        } else {
            save(newValue, as: name)
        }
    }

    func append<Value: JSON, T: Equatable>(_ newValues: [Value], to name: String, uniqBy keyPath: KeyPath<Value, T>) {
        if let value = retrieve(name, as: Value.self) {
            if newValues.firstIndex(where: { $0[keyPath: keyPath] == value[keyPath: keyPath] }) != nil {
                save(newValues, as: name)
                return
            }
            append(newValues, to: name)
        } else if var values = retrieve(name, as: [Value].self) {
            for newValue in newValues {
                if let index = values.firstIndex(where: { $0[keyPath: keyPath] == newValue[keyPath: keyPath] }) {
                    values[index] = newValue
                } else {
                    values.append(newValue)
                }
                save(values, as: name)
            }
        } else {
            save(newValues, as: name)
        }
    }

    func remove(_ name: String) {
        processQueue.safeSync {
            do {
                try Disk.remove(name, from: .documents)
            } catch {
                debug(.storage, "Failed to remove file '\(name)': \(error)")
            }
        }
    }

    func rename(_ name: String, to newName: String) {
        processQueue.safeSync {
            do {
                try Disk.rename(name, in: .documents, to: newName)
            } catch {
                debug(.storage, "Failed to rename file '\(name)' to '\(newName)': \(error)")
            }
        }
    }

    func transaction(_ exec: (FileStorage) -> Void) {
        processQueue.safeSync {
            exec(self)
        }
    }

    func urlFor(file: String) -> URL? {
        do {
            return try Disk.url(for: file, in: .documents)
        } catch {
            debug(.storage, "Failed to get URL for file '\(file)': \(error)")
            return nil
        }
    }
}

extension FileStorage {
    private func correctUnitParsingOffsets(_ parsedValue: Decimal) -> Decimal {
        Int(parsedValue) % 2 == 0 ? parsedValue : parsedValue + 1
    }

    func parseSettingIfMmolL(value: Decimal, threshold: Decimal = 39) -> Decimal {
        value < threshold ? correctUnitParsingOffsets(value.asMgdL) : value
    }

    /// Parses mmol/L settings stored on file to mg/dL if necessary and updates the preferences, settings,  insulin sensitivities, and glucose targets.
    /// - Returns: A boolean indicating whether any settings were parsed and updated.
    func parseOnFileSettingsToMgdL() -> Bool {
        debug(.businessLogic, "Check for mmol/L settings stored on file.")
        var wasParsed = false

        // Retrieve and parse preferences (Preferences struct)
        if var preferences = retrieve(OpenAPS.Settings.preferences, as: Preferences.self) {
            let initialThreshold = preferences.threshold_setting
            let initialSMBTarget = preferences.enableSMB_high_bg_target
            let initialExerciseTarget = preferences.halfBasalExerciseTarget

            preferences.threshold_setting = parseSettingIfMmolL(value: preferences.threshold_setting)
            preferences.enableSMB_high_bg_target = parseSettingIfMmolL(value: preferences.enableSMB_high_bg_target)
            preferences.halfBasalExerciseTarget = parseSettingIfMmolL(value: preferences.halfBasalExerciseTarget)

            if preferences.threshold_setting != initialThreshold ||
                preferences.enableSMB_high_bg_target != initialSMBTarget ||
                preferences.halfBasalExerciseTarget != initialExerciseTarget
            {
                debug(.businessLogic, "Preferences found in mmol/L. Parsing to mg/dL.")
                save(preferences, as: OpenAPS.Settings.preferences)
                wasParsed = true
            } else {
                debug(.businessLogic, "Preferences stored in mg/dL; no parsing required.")
            }
        }

        // Retrieve and parse settings (TrioSettings struct)
        if var settings = retrieve(OpenAPS.Settings.settings, as: TrioSettings.self) {
            let initialHigh = settings.high
            let initialLow = settings.low
            let initialHighGlucose = settings.highGlucose
            let initialLowGlucose = settings.lowGlucose

            settings.high = parseSettingIfMmolL(value: settings.high)
            settings.low = parseSettingIfMmolL(value: settings.low)
            settings.highGlucose = parseSettingIfMmolL(value: settings.highGlucose)
            settings.lowGlucose = parseSettingIfMmolL(value: settings.lowGlucose)

            if settings.high != initialHigh ||
                settings.low != initialLow ||
                settings.highGlucose != initialHighGlucose ||
                settings.lowGlucose != initialLowGlucose
            {
                debug(.businessLogic, "TrioSettings found in mmol/L. Parsing to mg/dL.")
                save(settings, as: OpenAPS.Settings.settings)
                wasParsed = true
            } else {
                debug(.businessLogic, "TrioSettings stored in mg/dL; no parsing required.")
            }
        }

        // Retrieve and parse insulin sensitivities
        if var sensitivities = retrieve(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self),
           sensitivities.units == .mmolL || sensitivities.userPreferredUnits == .mmolL
        {
            debug(.businessLogic, "Insulin sensitivities found in mmol/L. Parsing to mg/dL.")

            sensitivities.sensitivities = sensitivities.sensitivities.map { isf in
                InsulinSensitivityEntry(
                    sensitivity: parseSettingIfMmolL(value: isf.sensitivity),
                    offset: isf.offset,
                    start: isf.start
                )
            }
            sensitivities.units = .mgdL
            sensitivities.userPreferredUnits = .mgdL

            save(sensitivities, as: OpenAPS.Settings.insulinSensitivities)
            wasParsed = true
        } else {
            debug(.businessLogic, "Insulin sensitivities stored in mg/dL; no parsing required.")
        }

        // Retrieve and parse glucose targets
        if var glucoseTargets = retrieve(OpenAPS.Settings.bgTargets, as: BGTargets.self),
           glucoseTargets.units == .mmolL || glucoseTargets.userPreferredUnits == .mmolL
        {
            debug(.businessLogic, "Glucose target profile found in mmol/L. Parsing to mg/dL.")

            glucoseTargets.targets = glucoseTargets.targets.map { target in
                BGTargetEntry(
                    low: parseSettingIfMmolL(value: target.low),
                    high: parseSettingIfMmolL(value: target.high),
                    start: target.start,
                    offset: target.offset
                )
            }
            glucoseTargets.units = .mgdL
            glucoseTargets.userPreferredUnits = .mgdL

            save(glucoseTargets, as: OpenAPS.Settings.bgTargets)
            wasParsed = true
        } else {
            debug(.businessLogic, "Glucose target profile stored in mg/dL; no parsing required.")
        }

        return wasParsed
    }
}
