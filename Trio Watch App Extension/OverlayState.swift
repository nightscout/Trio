import SwiftUI

class OverlayState: ObservableObject {
    @Published var isVisible: Bool = false
    @Published var overlayContent = AnyView(EmptyView()) // Holds the content of the overlay

    func showOverlay<Content: View>(_ content: Content) {
        overlayContent = AnyView(content)
        isVisible = true
    }

    func hideOverlay() {
        isVisible = false
        overlayContent = AnyView(EmptyView())
    }
}
