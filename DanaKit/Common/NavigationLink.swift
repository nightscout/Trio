import SwiftUI

extension NavigationLink where Label == EmptyView, Destination == EmptyView {
    /// Useful in cases where a `NavigationLink` is needed but there should not be
    /// a destination. e.g. for programmatic navigation.
    static var empty: NavigationLink {
        self.init(destination: EmptyView(), label: { EmptyView() })
    }
}
