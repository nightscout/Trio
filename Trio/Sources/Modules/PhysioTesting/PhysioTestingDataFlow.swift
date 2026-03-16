import Foundation
import SwiftUI

enum PhysioTesting {
    enum Config {}

    enum TestType: String, CaseIterable, Identifiable {
        case pureCarbs = "pure_carbs"
        case carbsFat = "carbs_fat"
        case carbsProtein = "carbs_protein"
        case mixed = "mixed"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .pureCarbs:
                return String(localized: "Pure Carbs", comment: "Physio test type")
            case .carbsFat:
                return String(localized: "Carbs + Fat", comment: "Physio test type")
            case .carbsProtein:
                return String(localized: "Carbs + Protein", comment: "Physio test type")
            case .mixed:
                return String(localized: "Mixed Meal", comment: "Physio test type")
            }
        }

        var description: String {
            switch self {
            case .pureCarbs:
                return String(
                    localized: "Baseline absorption curve from pure carbs only",
                    comment: "Physio test type description"
                )
            case .carbsFat:
                return String(
                    localized: "Measure how fat delays and reshapes absorption",
                    comment: "Physio test type description"
                )
            case .carbsProtein:
                return String(
                    localized: "Measure how protein modifies absorption",
                    comment: "Physio test type description"
                )
            case .mixed:
                return String(
                    localized: "Test combined fat + protein interaction effect",
                    comment: "Physio test type description"
                )
            }
        }

        var dayNumber: Int {
            switch self {
            case .pureCarbs: return 1
            case .carbsFat: return 2
            case .carbsProtein: return 3
            case .mixed: return 4
            }
        }

        var iconName: String {
            switch self {
            case .pureCarbs: return "leaf.fill"
            case .carbsFat: return "drop.fill"
            case .carbsProtein: return "figure.strengthtraining.traditional"
            case .mixed: return "fork.knife"
            }
        }

        var requiresFat: Bool {
            self == .carbsFat || self == .mixed
        }

        var requiresProtein: Bool {
            self == .carbsProtein || self == .mixed
        }
    }

    enum TestPhase: String {
        case baseline = "Waiting for Baseline"
        case ready = "Ready to Start"
        case active = "Test Active"
        case rising = "BG Rising"
        case peaking = "BG Peaking"
        case descending = "BG Descending"
        case returning = "Returning to Flat"
        case complete = "Complete"
        case cancelled = "Cancelled"

        var displayName: String {
            String(localized: String.LocalizationValue(rawValue), comment: "Physio test phase")
        }
    }
}

protocol PhysioTestingProvider: Provider {}
