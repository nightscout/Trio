//
//  BluetoothPermissionStepView.swift
//  Trio
//
//  Created by Cengiz Deniz on 18.04.25.
//
import CoreBluetooth
import SwiftUI
import UIKit

struct BluetoothPermissionStepView: View {
    @Bindable var state: Onboarding.StateModel
    var bluetoothManager: BluetoothStateManager
    var currentStep: Binding<OnboardingStep>

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Enable device connectivity")
                .font(.title3)
                .bold()
                .multilineTextAlignment(.leading)

            Text("Trio requires Bluetooth to function as a (hybrid) closed‑loop system.")
                .font(.body)
                .multilineTextAlignment(.leading)
                .foregroundColor(Color.secondary)
                .padding(.bottom)

            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: "keyboard.onehanded.left.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Color.bgDarkBlue)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.primary.opacity(0.8)))
                    Text(
                        "Connect to your insulin pump so Trio can send dosing commands and stay active in the background."
                    )
                    .font(.body)
                    .foregroundColor(.primary)
                }

                HStack(spacing: 12) {
                    Image(systemName: "sensor.tag.radiowaves.forward.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Color.bgDarkBlue)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.primary.opacity(0.8)))
                    Text("Receive glucose readings every 5 minutes from your CGM to keep the loop running.")
                        .font(.body)
                        .foregroundColor(.primary)
                }
            }

            Text("You can change these permissions any time in the iOS Settings app.")
                .font(.footnote)
                .multilineTextAlignment(.leading)
                .foregroundColor(Color.secondary)
                .padding(.top)
        }
        .padding(.horizontal)
        .background(
            SystemAlert(
                isPresented: $state.shouldDisplayBluetoothRequestAlert,
                title: String(localized: "“Trio” Would Like to Use Bluetooth"),
                message: String(
                    localized: "Bluetooth is used to communicate with insulin pump and continuous glucose monitor devices."
                ),
                allowTitle: String(localized: "Allow"),
                denyTitle: String(localized: "Don’t Allow"),
                onAllow: {
                    /// Requests Bluetooth permission and updates onboarding state based on the system’s response.
                    /// It calls `authorizeBluetooth`, which initializes `CBCentralManager` and triggers the
                    /// native system permission prompt (if not previously shown).
                    ///
                    /// The resulting authorization is checked — if the user grants permission (`.authorized`),
                    /// `hasBluetoothGranted` is set to `true`, allowing the app to proceed with Bluetooth operations.
                    /// Otherwise, it remains `false`, and the user can be guided to manually enable Bluetooth later.
                    ///
                    /// This ensures the app only treats Bluetooth as granted when the system confirms it.
                    bluetoothManager.authorizeBluetooth { auth in
                        DispatchQueue.main.async {
                            state.hasBluetoothGranted = (auth == .authorized)
                            state.shouldDisplayBluetoothRequestAlert = false
                            if let next = currentStep.wrappedValue.next {
                                currentStep.wrappedValue = next
                            }
                        }
                    }
                },
                onDeny: {
                    /// Requests Bluetooth permission and updates onboarding state based on the system’s response.
                    /// Although `authorizeBluetooth` is still called (to ensure iOS shows the app under
                    /// Settings > Privacy & Security > Bluetooth), the app forcibly sets `hasBluetoothGranted` to `false`
                    /// regardless of the system-reported authorization status.
                    ///
                    /// This ensures the app tracks user intent correctly (denial),
                    /// while still letting the system recognize Bluetooth usage,
                    /// so users can later re-enable it manually in iOS Settings.
                    bluetoothManager.authorizeBluetooth { _ in
                        DispatchQueue.main.async {
                            state.hasBluetoothGranted = false
                            state.shouldDisplayBluetoothRequestAlert = false
                            if let next = currentStep.wrappedValue.next {
                                currentStep.wrappedValue = next
                            }
                        }
                    }
                }
            )
        )
    }
}

/// Presents a real UIAlertController, pinned to the system's own style
///
/// Why use this?
/// SwiftUI’s built‑in .alert will always inherit the color scheme of its host view (in our case, we have forced .dark for the entire onboarding screen).
/// There’s no way to tell SwiftUI “use the system setting here only for this one alert.”
/// The workaround is to present a plain UIKit UIAlertController ourself, in its own representable, and explicitly tell it to use the system’s interface style instead of inheriting our forced dark mode.
/// We enforce usage of the system's interface style by setting its overrideUserInterfaceStyle to whatever the device is actually using (.light or .dark).
struct SystemAlert: UIViewControllerRepresentable {
    @Binding var isPresented: Bool

    let title: String
    let message: String
    let allowTitle: String
    let denyTitle: String

    /// called after Allow or Deny
    let onAllow: () -> Void
    let onDeny: () -> Void

    func makeUIViewController(context _: Context) -> UIViewController {
        // empty container
        UIViewController()
    }

    func updateUIViewController(_ uiVC: UIViewController, context _: Context) {
        guard isPresented, uiVC.presentedViewController == nil else { return }

        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )

        // force it back to the "real" system style
        let systemStyle = UIScreen.main.traitCollection.userInterfaceStyle
        alert.overrideUserInterfaceStyle = systemStyle

        alert.addAction(.init(title: denyTitle, style: .cancel) { _ in
            isPresented = false
            onDeny()
        })
        alert.addAction(.init(title: allowTitle, style: .default) { _ in
            isPresented = false
            onAllow()
        })

        uiVC.present(alert, animated: true)
    }
}
