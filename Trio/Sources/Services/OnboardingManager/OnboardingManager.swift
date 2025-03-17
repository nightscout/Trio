import Foundation
import SwiftUI
import Swinject

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

/// Manages the app's onboarding experience, ensuring it's only shown to new users.
/// Coordinates the display of onboarding screens when the app is launched for the first time.
final class OnboardingManager: Injectable, ObservableObject {
    @Injected() var settingsManager: SettingsManager!

    /// Indicates whether the onboarding flow should be presented.
    @Published var shouldShowOnboarding: Bool = false

    /// Initialize the OnboardingManager with the required dependencies.
    init(resolver: Resolver) {
        injectServices(resolver)
        checkOnboardingStatus()
    }

    /// Checks if onboarding has been completed and updates the shouldShowOnboarding flag accordingly.
    private func checkOnboardingStatus() {
        shouldShowOnboarding = !UserDefaults.standard.onboardingCompleted
    }

    /// Marks onboarding as completed and updates the shouldShowOnboarding flag.
    func completeOnboarding() {
        UserDefaults.standard.onboardingCompleted = true
        shouldShowOnboarding = false
    }

    /// Resets the onboarding status for testing purposes.
    func resetOnboarding() {
        UserDefaults.standard.onboardingCompleted = false
        shouldShowOnboarding = true
    }
}
