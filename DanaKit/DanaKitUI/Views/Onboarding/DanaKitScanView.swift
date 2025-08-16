import LoopKitUI
import SwiftUI

struct DanaKitScanView: View {
    @Environment(\.isPresented) var isPresented
    @Environment(\.dismissAction) private var dismiss

    @ObservedObject var viewModel: DanaKitScanViewModel

    var body: some View {
        VStack(alignment: .leading) {
            Text(LocalizedString("Found Dana-i/RS pumps", comment: "Title for DanaKitScanView"))
                .font(.title)
                .bold()
                .padding(.horizontal)

            HStack(alignment: .center, spacing: 0) {
                Text(
                    !$viewModel.isConnecting.wrappedValue ?
                        LocalizedString("Scanning", comment: "Scanning text") :
                        LocalizedString("Connecting", comment: "Connecting text")
                )
                Spacer()
                ActivityIndicator(isAnimating: .constant(true), style: .medium)
            }
            .padding(.horizontal)

            Divider()
            content
        }

        .navigationBarHidden(false)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(LocalizedString("Cancel", comment: "Cancel button title"), action: {
                    viewModel.stopScan()
                    self.dismiss()
                })
            }
        }
        .onChange(of: isPresented) { newValue in
            if !newValue {
                viewModel.stopScan()
            }
        }
        .alert(
            LocalizedString("Error while connecting to device", comment: "Connection error message"),
            isPresented: $viewModel.isConnectionError,
            presenting: $viewModel.connectionErrorMessage,
            actions: { _ in
                Button(LocalizedString("Oke", comment: "Dana-RS v3 pincode prompt oke"), action: {})
            },
            message: { detail in Text(detail.wrappedValue ?? "") }
        )
        .alert(
            LocalizedString("Dana-RS v3 found!", comment: "Dana-RS v3 found"),
            isPresented: $viewModel.isPromptingPincode
        ) {
            Button(LocalizedString("Cancel", comment: "Cancel button title"), role: .cancel) {
                viewModel.cancelPinPrompt()
            }
            Button(LocalizedString("Oke", comment: "Dana-RS v3 pincode prompt oke")) {
                viewModel.processPinPrompt()
            }

            TextField(LocalizedString("Pin 1", comment: "Dana-RS v3 pincode prompt pin 1"), text: $viewModel.pin1)
            TextField(LocalizedString("Pin 2", comment: "Dana-RS v3 pincode prompt pin 2"), text: $viewModel.pin2)
        } message: {
            if let message = $viewModel.pinCodePromptError.wrappedValue {
                Text(message)
            }
        }
    }

    @ViewBuilder private var content: some View {
        List($viewModel.scannedDevices) { $result in
            Button(action: { viewModel.connect($result.wrappedValue) }) {
                HStack {
                    Text($result.name.wrappedValue)
                    Spacer()
                    if !$viewModel.isConnecting.wrappedValue {
                        NavigationLink.empty
                    } else if $result.name.wrappedValue == viewModel.connectingTo {
                        ActivityIndicator(isAnimating: .constant(true), style: .medium)
                    }
                }
                .padding(.horizontal)
            }
            .disabled($viewModel.isConnecting.wrappedValue)
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
    }
}

#Preview {
    DanaKitScanView(viewModel: DanaKitScanViewModel(nextStep: {}))
}
