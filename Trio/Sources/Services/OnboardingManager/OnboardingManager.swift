import Foundation
import SwiftUI
import Swinject

/// Manages the app's onboarding experience, ensuring it's only shown to new users.
/// Coordinates the display of onboarding screens when the app is launched for the first time.
@Observable final class OnboardingManager: Injectable {
    /// Shared singleton instance.
    static let shared = OnboardingManager()

    /// Indicates whether the onboarding flow should be presented.
    var shouldShowOnboarding: Bool = false

    /// Initialize the OnboardingManager with the required dependencies.
    init() {
        checkOnboardingStatus()
    }

    /// Checks if onboarding has been completed and updates the shouldShowOnboarding flag accordingly.
    private func checkOnboardingStatus() {
        shouldShowOnboarding = !(PropertyPersistentFlags.shared.onboardingCompleted ?? false)
    }

    /// Marks onboarding as completed and updates the shouldShowOnboarding flag.
    func completeOnboarding() {
        PropertyPersistentFlags.shared.onboardingCompleted = true
        shouldShowOnboarding = false
    }

    /// Resets the onboarding status for testing purposes.
    func resetOnboarding() {
        PropertyPersistentFlags.shared.onboardingCompleted = false
        shouldShowOnboarding = true
    }
}

extension UserDefaults {
    /// Flag that indicates if onboarding has been completed.
    var onboardingCompleted: Bool {
        get {
            bool(forKey: "onboardingCompleted")
        }
        set {
            set(newValue, forKey: "onboardingCompleted")
        }
    }
}
