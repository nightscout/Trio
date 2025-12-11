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
    }

    struct PatternDetected: Codable, Equatable, Identifiable {
        var id: String { patternType + description }
        let patternType: String
        let description: String
        let frequency: String
        let impact: String
        let confidence: ConfidenceLevel
    }

    struct RecommendedProfile: Codable, Equatable {
        let basalRates: [BasalRateRecommendation]
        let isfValues: [ISFRecommendation]
        let crValues: [CRRecommendation]
    }

    struct BasalRateRecommendation: Codable, Equatable, Identifiable {
        var id: String { time }
        let time: String
        let currentValue: Decimal
        let recommendedValue: Decimal
        let change: Decimal
        let percentChange: Double
    }

    struct ISFRecommendation: Codable, Equatable, Identifiable {
        var id: String { time }
        let time: String
        let currentValue: Decimal
        let recommendedValue: Decimal
        let change: Decimal
        let percentChange: Double
    }

    struct CRRecommendation: Codable, Equatable, Identifiable {
        var id: String { time }
        let time: String
        let currentValue: Decimal
        let recommendedValue: Decimal
        let change: Decimal
        let percentChange: Double
    }

    struct ProfileAdjustment: Codable, Equatable, Identifiable {
        var id: String { parameter + timePeriod }
        let parameter: String
        let timePeriod: String
        let oldValue: String
        let newValue: String
        let percentChange: Double
        let rationale: String
        let confidence: ConfidenceLevel
        let priority: Int // 1-5, 1 being highest priority
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
    static func parse(from jsonString: String) -> ClaudeOTuneRecommendation? {
        // Try to extract JSON from the response (Claude may include markdown)
        var jsonToParse = jsonString

        // Look for JSON block markers
        if let jsonStart = jsonString.range(of: "```json"),
           let jsonEnd = jsonString.range(of: "```", range: jsonStart.upperBound..<jsonString.endIndex) {
            jsonToParse = String(jsonString[jsonStart.upperBound..<jsonEnd.lowerBound])
        } else if let jsonStart = jsonString.firstIndex(of: "{"),
                  let jsonEnd = jsonString.lastIndex(of: "}") {
            jsonToParse = String(jsonString[jsonStart...jsonEnd])
        }

        guard let data = jsonToParse.data(using: .utf8) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            return try decoder.decode(ClaudeOTuneRecommendation.self, from: data)
        } catch {
            print("Claude-o-Tune JSON parsing error: \(error)")
            return nil
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
