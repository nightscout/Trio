import SwiftUI

class NavigationState: ObservableObject {
    @Published var path = NavigationPath() // Tracks the navigation stack

    func resetToRoot() {
        path.removeLast(path.count) // Clears the navigation stack to return to root
    }
}

enum NavigationDestinations: String {
    case carbInput
    case bolusInput
    case bolusConfirm
}
