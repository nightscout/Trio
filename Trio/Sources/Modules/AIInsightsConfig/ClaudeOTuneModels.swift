import Foundation

// MARK: - Claude-o-Tune Data Models

/// Represents a complete Claude-o-Tune profile recommendation
struct ClaudeOTuneRecommendation: Codable, Equatable {
    let analysisSummary: String
    let dataQuality: DataQuality
    let currentMetrics: CurrentMetrics
    let patternsDetected: [PatternDetected]
    let recommendedProfile: RecommendedProfile
    let adjustments: [ProfileAdjustment]
    let concerns: [SafetyConcern]
    let confidence: ConfidenceLevel
    let explanation: String

    enum CodingKeys: String, CodingKey {
        case analysisSummary = "analysis_summary"
        case dataQuality = "data_quality"
        case currentMetrics = "current_metrics"
        case patternsDetected = "patterns_detected"
        case recommendedProfile = "recommended_profile"
        case adjustments
        case concerns
        case confidence
        case explanation
    }

    struct DataQuality: Codable, Equatable {
        let score: Int // 0-100
        let issues: [String]
    }

    struct CurrentMetrics: Codable, Equatable {
        let timeInRange: Double
        let timeBelowRange: Double
        let timeAboveRange: Double
        let averageGlucose: Int
        let glucoseVariability: Double
        let gmi: Double

        enum CodingKeys: String, CodingKey {
            case timeInRange = "time_in_range"
            case timeBelowRange = "time_below_range"
            case timeAboveRange = "time_above_range"
            case averageGlucose = "average_glucose"
            case glucoseVariability = "glucose_variability"
            case gmi
        }
    }

    struct PatternDetected: Codable, Equatable, Identifiable {
        var id: String { patternType + description }
        let patternType: String
        let description: String
        let frequency: String
        let impact: String
        let confidence: ConfidenceLevel

        enum CodingKeys: String, CodingKey {
            case patternType = "pattern_type"
            case description
            case frequency
            case impact
            case confidence
        }
    }

    struct RecommendedProfile: Codable, Equatable {
        let basalRates: [BasalRateRecommendation]
        let isfValues: [ISFRecommendation]
        let crValues: [CRRecommendation]

        enum CodingKeys: String, CodingKey {
            case basalRates = "basal_rates"
            case isfValues = "isf_values"
            case crValues = "cr_values"
        }
    }

    struct BasalRateRecommendation: Codable, Equatable, Identifiable {
        var id: String { time }
        let time: String
        let currentValue: Double
        let recommendedValue: Double
        let change: Double
        let percentChange: Double

        enum CodingKeys: String, CodingKey {
            case time
            case currentValue = "current_value"
            case recommendedValue = "recommended_value"
            case change
            case percentChange = "percent_change"
        }
    }

    struct ISFRecommendation: Codable, Equatable, Identifiable {
        var id: String { time }
        let time: String
        let currentValue: Double
        let recommendedValue: Double
        let change: Double
        let percentChange: Double

        enum CodingKeys: String, CodingKey {
            case time
            case currentValue = "current_value"
            case recommendedValue = "recommended_value"
            case change
            case percentChange = "percent_change"
        }
    }

    struct CRRecommendation: Codable, Equatable, Identifiable {
        var id: String { time }
        let time: String
        let currentValue: Double
        let recommendedValue: Double
        let change: Double
        let percentChange: Double

        enum CodingKeys: String, CodingKey {
            case time
            case currentValue = "current_value"
            case recommendedValue = "recommended_value"
            case change
            case percentChange = "percent_change"
        }
    }

    struct ProfileAdjustment: Codable, Equatable, Identifiable {
        var id: String { parameter + timePeriod }
        let parameter: String
        let timePeriod: String
        let oldValue: Double
        let newValue: Double
        let percentChange: Double
        let rationale: String
        let confidence: ConfidenceLevel
        let priority: Int // 1-5, 1 being highest priority

        enum CodingKeys: String, CodingKey {
            case parameter
            case timePeriod = "time_period"
            case oldValue = "old_value"
            case newValue = "new_value"
            case percentChange = "percent_change"
            case rationale
            case confidence
            case priority
        }
    }

    struct SafetyConcern: Codable, Equatable, Identifiable {
        var id: String { description }
        let severity: Severity
        let description: String
        let recommendation: String

        enum Severity: String, Codable, Equatable {
            case low
            case medium
            case high

            var displayName: String {
                rawValue.capitalized
            }
        }
    }

    enum ConfidenceLevel: String, Codable, Equatable {
        case low
        case medium
        case high

        var displayName: String {
            rawValue.capitalized
        }
    }
}

// MARK: - Claude-o-Tune Settings

struct ClaudeOTuneSettings: Codable, Equatable {
    var timePeriod: Int = 30 // days
    var includePatternAnalysis: Bool = true
    var includeBasalRecommendations: Bool = true
    var includeISFRecommendations: Bool = true
    var includeCRRecommendations: Bool = true
    var maxAdjustmentPercent: Double = 20.0 // Maximum % change per recommendation
    var customPrompt: String = ""

    /// Respects safety bounds from the algorithm
    var autosensMax: Double = 1.2
    var autosensMin: Double = 0.7
}

// MARK: - JSON Parsing Helpers

extension ClaudeOTuneRecommendation {
    /// Attempts to parse a Claude-o-Tune recommendation from JSON response text
    /// Returns a tuple with the recommendation (if successful) and any error message
    static func parse(from jsonString: String) -> (recommendation: ClaudeOTuneRecommendation?, error: String?) {
        // Try to extract JSON from the response (Claude may include markdown)
        var jsonToParse = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        // Look for JSON block markers
        if let jsonStart = jsonString.range(of: "```json"),
           let jsonEnd = jsonString.range(of: "```", range: jsonStart.upperBound..<jsonString.endIndex) {
            jsonToParse = String(jsonString[jsonStart.upperBound..<jsonEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let jsonStart = jsonString.firstIndex(of: "{"),
                  let jsonEnd = jsonString.lastIndex(of: "}") {
            jsonToParse = String(jsonString[jsonStart...jsonEnd])
        }

        guard let data = jsonToParse.data(using: .utf8) else {
            return (nil, "Failed to convert response to data")
        }

        let decoder = JSONDecoder()
        // Note: Using explicit CodingKeys instead of .convertFromSnakeCase for reliability

        do {
            let result = try decoder.decode(ClaudeOTuneRecommendation.self, from: data)
            return (result, nil)
        } catch let DecodingError.keyNotFound(key, context) {
            let errorMsg = "Missing key '\(key.stringValue)' in \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
            print("Claude-o-Tune JSON parsing error: \(errorMsg)")
            return (nil, errorMsg)
        } catch let DecodingError.typeMismatch(type, context) {
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            let errorMsg = "Type mismatch for \(type) at '\(path)': \(context.debugDescription)"
            print("Claude-o-Tune JSON parsing error: \(errorMsg)")
            return (nil, errorMsg)
        } catch let DecodingError.valueNotFound(type, context) {
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            let errorMsg = "Value not found for \(type) at '\(path)'"
            print("Claude-o-Tune JSON parsing error: \(errorMsg)")
            return (nil, errorMsg)
        } catch let DecodingError.dataCorrupted(context) {
            let errorMsg = "Data corrupted: \(context.debugDescription)"
            print("Claude-o-Tune JSON parsing error: \(errorMsg)")
            return (nil, errorMsg)
        } catch {
            print("Claude-o-Tune JSON parsing error: \(error)")
            return (nil, "JSON parsing failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Comparison with Current Profile

extension ClaudeOTuneRecommendation {
    /// Returns true if any recommendations exceed the configured safety bounds
    func hasRecommendationsExceedingBounds(maxPercent: Double) -> Bool {
        for adjustment in adjustments {
            if abs(adjustment.percentChange) > maxPercent {
                return true
            }
        }
        return false
    }

    /// Returns the total number of recommended changes
    var totalRecommendedChanges: Int {
        var count = 0
        count += recommendedProfile.basalRates.filter { $0.change != 0 }.count
        count += recommendedProfile.isfValues.filter { $0.change != 0 }.count
        count += recommendedProfile.crValues.filter { $0.change != 0 }.count
        return count
    }

    /// Returns high priority adjustments (priority 1-2)
    var highPriorityAdjustments: [ProfileAdjustment] {
        adjustments.filter { $0.priority <= 2 }
    }
}
