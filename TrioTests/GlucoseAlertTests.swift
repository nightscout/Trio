import Foundation
import Testing

@testable import Trio

@Suite("Trio Alerts: GlucoseAlert") struct GlucoseAlertTests {
    // MARK: - Group A: shouldEvaluate

    @Test("urgentLow evaluates even when isEnabled is false") func urgentLowDisabledStillEvaluates() {
        var a = GlucoseAlert(type: .urgentLow)
        a.isEnabled = false
        #expect(a.shouldEvaluate == true)
    }

    @Test("urgentLow evaluates when isEnabled is true") func urgentLowEnabledEvaluates() {
        var a = GlucoseAlert(type: .urgentLow)
        a.isEnabled = true
        #expect(a.shouldEvaluate == true)
    }

    @Test("low does not evaluate when disabled") func lowDisabledDoesNotEvaluate() {
        var a = GlucoseAlert(type: .low)
        a.isEnabled = false
        #expect(a.shouldEvaluate == false)
    }

    @Test("low evaluates when enabled") func lowEnabledEvaluates() {
        var a = GlucoseAlert(type: .low)
        a.isEnabled = true
        #expect(a.shouldEvaluate == true)
    }

    @Test("high does not evaluate when disabled") func highDisabledDoesNotEvaluate() {
        var a = GlucoseAlert(type: .high)
        a.isEnabled = false
        #expect(a.shouldEvaluate == false)
    }

    @Test("high evaluates when enabled") func highEnabledEvaluates() {
        var a = GlucoseAlert(type: .high)
        a.isEnabled = true
        #expect(a.shouldEvaluate == true)
    }

    @Test("forecastedLow does not evaluate when disabled") func forecastedLowDisabledDoesNotEvaluate() {
        var a = GlucoseAlert(type: .forecastedLow)
        a.isEnabled = false
        #expect(a.shouldEvaluate == false)
    }

    @Test("forecastedLow evaluates when enabled") func forecastedLowEnabledEvaluates() {
        var a = GlucoseAlert(type: .forecastedLow)
        a.isEnabled = true
        #expect(a.shouldEvaluate == true)
    }

    // MARK: - Group B: decoder defaults

    @Test("Omitted isEnabled defaults to true") func decodeOmittedIsEnabledDefaultsTrue() throws {
        let json = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "type": "low",
            "name": "Low Glucose",
            "thresholdMgDL": 72
        }
        """
        let decoded = try JSONDecoder().decode(GlucoseAlert.self, from: Data(json.utf8))
        #expect(decoded.isEnabled == true)
    }

    @Test("urgentLow with isEnabled false decodes false but still evaluates") func decodeUrgentLowDisabledStillEvaluates() throws {
        let json = """
        {
            "id": "22222222-2222-2222-2222-222222222222",
            "type": "urgentLow",
            "name": "Urgent Low Glucose",
            "isEnabled": false,
            "thresholdMgDL": 54
        }
        """
        let decoded = try JSONDecoder().decode(GlucoseAlert.self, from: Data(json.utf8))
        #expect(decoded.isEnabled == false)
        #expect(decoded.shouldEvaluate == true)
    }

    @Test("high with optional fields omitted uses type defaults") func decodeHighDefaults() throws {
        let json = """
        {
            "id": "33333333-3333-3333-3333-333333333333",
            "type": "high",
            "name": "High Glucose",
            "thresholdMgDL": 270
        }
        """
        let decoded = try JSONDecoder().decode(GlucoseAlert.self, from: Data(json.utf8))
        #expect(decoded.soundFilename == GlucoseAlertType.high.defaultSoundFilename)
        #expect(decoded.playsSound == true)
        #expect(decoded.overridesSilenceAndDND == false)
        #expect(decoded.activeOption == .always)
        #expect(decoded.snoozedUntil == nil)
        #expect(decoded.isEnabled == true)
    }

    @Test("urgentLow with overridesSilenceAndDND omitted uses type defaults") func decodeUrgentLowOverrideDefault() throws {
        let json = """
        {
            "id": "44444444-4444-4444-4444-444444444444",
            "type": "urgentLow",
            "name": "Urgent Low Glucose",
            "thresholdMgDL": 54
        }
        """
        let decoded = try JSONDecoder().decode(GlucoseAlert.self, from: Data(json.utf8))
        #expect(decoded.overridesSilenceAndDND == true)
        #expect(decoded.soundFilename == GlucoseAlertType.urgentLow.defaultSoundFilename)
    }

    // MARK: - Group C: round-trip

    @Test("Fully-populated value survives encode/decode round-trip") func roundTrip() throws {
        var original = GlucoseAlert(type: .low)
        original.name = "Custom Low Alarm"
        original.isEnabled = false
        original.thresholdMgDL = 65
        original.soundFilename = "custom_sound.caf"
        original.playsSound = false
        original.overridesSilenceAndDND = true
        original.activeOption = .night
        original.snoozedUntil = Date(timeIntervalSinceReferenceDate: 1_000_000)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GlucoseAlert.self, from: data)
        #expect(decoded == original)
    }
}
