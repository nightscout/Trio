import SwiftUI

extension Image {
    init(danaImage: String) {
        self.init(uiImage: UIImage(named: danaImage, in: Bundle(for: DanaKitHUDProvider.self), compatibleWith: nil)!)
    }
}
