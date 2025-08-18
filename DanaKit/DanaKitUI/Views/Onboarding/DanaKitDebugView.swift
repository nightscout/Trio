import SwiftUI

struct DanaKitDebugView: View {
    @Environment(\.openURL) var openURL
    @ObservedObject var viewModel: DanaKitDebugViewModel
    @State private var isSharePresented: Bool = false

    var body: some View {
        VStack {
            HStack {
                Button("Scan", action: viewModel.scan)
                    .frame(width: 100, height: 100)

                Button("Connect", action: viewModel.connect)
                    .disabled(viewModel.scannedDevices.isEmpty)
                    .frame(width: 100, height: 100)
            }

            HStack {
                Button("Do bolus", action: viewModel.bolusModal)
                    .disabled(viewModel.isConnected == false)
                    .frame(width: 100, height: 100)

                Button("Stop bolus", action: viewModel.stopBolus)
                    .disabled(viewModel.isConnected == false)
                    .frame(width: 100, height: 100)
            }

            HStack {
                Button("temp basal", action: viewModel.tempBasalModal)
                    .disabled(viewModel.isConnected == false)
                    .frame(width: 100, height: 100)

                Button("Stop temp basal", action: viewModel.stopTempBasal)
                    .disabled(viewModel.isConnected == false)
                    .frame(width: 100, height: 100)
            }

            HStack {
                Button("Basal", action: viewModel.basal)
                    .disabled(viewModel.isConnected == false)
                    .frame(width: 100, height: 100)

                Button("Disconnect", action: viewModel.disconnect)
                    .disabled(viewModel.isConnected == false)
                    .frame(width: 100, height: 100)
            }

            HStack {
                Button(LocalizedString("Share Dana pump logs", comment: "DanaKit share logs")) {
                    self.isSharePresented = true
                }
                .sheet(isPresented: $isSharePresented, onDismiss: {}, content: {
                    ActivityViewController(activityItems: viewModel.getLogs())
                })
            }
        }
        .alert(
            "Device found!",
            isPresented: $viewModel.isPresentingScanAlert,
            presenting: viewModel.messageScanAlert,
            actions: { _ in
                Button("No", action: {})
                Button("Yes", action: viewModel.connect)
            },
            message: { detail in Text(detail) }
        )
        .alert(
            "Error while starting scanning for devices...",
            isPresented: $viewModel.isPresentingScanningErrorAlert,
            presenting: viewModel.scanningErrorMessage,
            actions: { _ in
                Button("Oke", action: {})
            },
            message: { detail in Text(detail) }
        )
        .alert(
            LocalizedString("Error while connecting to device", comment: "Connection error message"),
            isPresented: $viewModel.isConnectionError,
            presenting: $viewModel.connectionErrorMessage,
            actions: { _ in
                Button("Oke", action: {})
            },
            message: { detail in Text(detail.wrappedValue ?? "") }
        )
        .alert(
            "DEBUG: Bolus action",
            isPresented: $viewModel.isPresentingBolusAlert,
            actions: {
                Button("No", action: {})
                Button("Yes", action: viewModel.bolus)
            },
            message: { Text("Are you sure you want to bolus 5E?") }
        )
        .alert(
            "DEBUG: Temp basal action",
            isPresented: $viewModel.isPresentingTempBasalAlert,
            actions: {
                Button("No", action: {})
                Button("Yes", action: viewModel.tempBasal)
            },
            message: { Text("Are you sure you want to set the temp basal to 200% for 1 hour?") }
        )
        .alert(
            LocalizedString("Dana-RS v3 found!", comment: "Dana-RS v3 found"),
            isPresented: $viewModel.isPromptingPincode
        ) {
            Button(LocalizedString("Cancel", comment: "Cancel button title"), role: .cancel) {
                viewModel.cancelPinPrompt()
            }
            Button(LocalizedString("Oke", comment: "Dana-RS v3 pincode prompt oke"), action: {
                viewModel.processPinPrompt()
            })

            TextField(LocalizedString("Pin 1", comment: "Dana-RS v3 pincode prompt pin 1"), text: $viewModel.pin1)
            TextField(LocalizedString("Pin 2", comment: "Dana-RS v3 pincode prompt pin 2"), text: $viewModel.pin2)
        } message: {
            if let message = $viewModel.pinCodePromptError.wrappedValue {
                Text(message)
            }
        }
    }
}

#Preview {
    DanaKitDebugView(viewModel: DanaKitDebugViewModel())
}
