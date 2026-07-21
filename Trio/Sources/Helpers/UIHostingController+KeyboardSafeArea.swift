import SwiftUI

/// Lets us reach the WindowGroup's generic root hosting controller without
/// knowing its view type, to exclude the keyboard from its safe area.
protocol KeyboardSafeAreaExcludable {
    func excludeKeyboardFromSafeArea()
}

extension UIHostingController: KeyboardSafeAreaExcludable {
    func excludeKeyboardFromSafeArea() {
        if #available(iOS 16.4, *) {
            safeAreaRegions = .container
        }
    }
}

extension UIViewController {
    /// Walk down to the root hosting controller and drop its keyboard safe area.
    /// iOS sometimes replays a stale keyboard frame on foreground, which
    /// compresses the keyboard-free home layout until a rotation recomputes it.
    func excludeKeyboardFromSafeAreaTree() {
        (self as? KeyboardSafeAreaExcludable)?.excludeKeyboardFromSafeArea()
        for child in children {
            child.excludeKeyboardFromSafeAreaTree()
        }
    }
}
