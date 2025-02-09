import SwiftUI

enum Main {
    enum Config {}

    struct Modal: Identifiable {
        let screen: Screen
        let view: AnyView

        var id: Int { screen.id }
    }
}

protocol MainProvider: Provider {}
