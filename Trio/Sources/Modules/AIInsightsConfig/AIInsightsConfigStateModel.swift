import Combine
import SwiftUI

extension AIInsightsConfig {
    final class StateModel: BaseStateModel<Provider> {
        // Placeholder state - will be expanded later
        @Published var isConfigured = false

        override func subscribe() {
            // Will be implemented when we add actual functionality
        }
    }
}
