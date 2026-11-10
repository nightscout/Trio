import LoopKit
import LoopKitUI
import SwiftUI
import Swinject
import UIKit

/// A watch plugin's setup or settings, shown over the Watch screen.
enum SmartwatchSheet: Identifiable {
    case setup(identifier: String)
    case settings

    var id: String {
        switch self {
        case let .setup(identifier): "setup-\(identifier)"
        case .settings: "settings"
        }
    }
}

/// The Watch screen's sections for watches other than Apple Watch (watch
/// plugins such as Pebble): one row per available plugin until a watch is
/// added, then the added watch, which opens the plugin's own settings (where
/// the plugin also has what the watch may ask Trio to do). The screen presents
/// `sheet` (`smartwatchSheets`):
/// these are several list rows, and a sheet attached to them would be
/// attached to each, so a tap would present it more than once and close it.
struct WatchConfigSmartwatchSections: View {
    let resolver: Resolver
    @Binding var sheet: SmartwatchSheet?

    private var host: SmartwatchHost { resolver.resolve(SmartwatchHost.self)! }

    var body: some View {
        let manager = host.smartwatchManager
        Section(
            header: Text(String(
                localized: "Third-Party Smartwatch",
                comment: "Watch screen: header of the section for watches other than Apple Watch"
            )),
            footer: Text(
                manager == nil
                    ? String(
                        localized: "Add a watch other than Apple Watch here. Apple Watch uses Trio's own watch app, above.",
                        comment: "Watch screen: footer while no third-party watch is added"
                    )
                    : String(
                        localized: "A watch other than Apple Watch: it shows your glucose and Trio's glucose alerts.",
                        comment: "Watch screen: footer once a third-party watch is added"
                    )
            )
        ) {
            if let manager {
                Button { sheet = .settings } label: {
                    row(title: manager.localizedTitle, image: manager.smallImage)
                }
            } else {
                ForEach(host.availableSmartwatchManagers, id: \.identifier) { descriptor in
                    Button { sheet = .setup(identifier: descriptor.identifier) } label: {
                        row(title: descriptor.localizedTitle, image: descriptor.image, subtitle: descriptor.subtitle)
                    }
                }
            }
        }
        .listRowBackground(Color.chart)
    }

    private func row(title: String, image: UIImage?, subtitle: String? = nil) -> some View {
        HStack(spacing: 12) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundColor(.primary)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundColor(.secondary)
        }
    }
}

extension View {
    /// Presents the watch plugin's setup or settings for `sheet`, once for the
    /// whole screen, and counts `revision` up when a watch is added or removed.
    func smartwatchSheets(resolver: Resolver, sheet: Binding<SmartwatchSheet?>, revision: Binding<Int>) -> some View {
        let host = resolver.resolve(SmartwatchHost.self)!
        return self
            .sheet(item: sheet) { item in
                SmartwatchViewControllerView { completionDelegate in
                    switch item {
                    case let .setup(identifier):
                        host.setupViewController(for: identifier, completionDelegate: completionDelegate)
                    case .settings:
                        host.settingsViewController(completionDelegate: completionDelegate)
                    }
                } onComplete: {
                    sheet.wrappedValue = nil
                }
                .ignoresSafeArea()
                .interactiveDismissDisabled()
            }
            .onReceive(host.smartwatchManagerChanged.receive(on: DispatchQueue.main)) { _ in
                revision.wrappedValue += 1
            }
    }
}

/// Hosts a plugin's setup or settings view controller and closes the sheet when
/// the plugin reports it is done.
private struct SmartwatchViewControllerView: UIViewControllerRepresentable {
    let makeViewController: @MainActor(CompletionDelegate) -> UIViewController?
    let onComplete: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        guard let viewController = makeViewController(context.coordinator) else {
            // Set up without user interaction, or nothing to show.
            DispatchQueue.main.async(execute: onComplete)
            return UIViewController()
        }
        return viewController
    }

    func updateUIViewController(_: UIViewController, context _: Context) {}

    final class Coordinator: CompletionDelegate {
        let onComplete: () -> Void

        init(onComplete: @escaping () -> Void) {
            self.onComplete = onComplete
        }

        func completionNotifyingDidComplete(_: CompletionNotifying) {
            DispatchQueue.main.async(execute: onComplete)
        }
    }
}
