import SwiftUI
import UIKit

struct ActivityViewController: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context _: UIViewControllerRepresentableContext<ActivityViewController>)
        -> UIActivityViewController
    {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }

    func updateUIViewController(
        _: UIActivityViewController,
        context _: UIViewControllerRepresentableContext<ActivityViewController>
    ) {}
}
