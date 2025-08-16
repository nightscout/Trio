import LoopKitUI
import SwiftUI

struct DanaKitRefillReservoirAndCannulaView: View {
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>
    @ObservedObject var viewModel: DanaKitRefillReservoirCannulaViewModel

    @State var isEditingReservoirAmount = false
    @State var isEditingTubeRefillAmount = false
    @State var isEditingPrimeRefillAmount = false

    let unitText = LocalizedString("U", comment: "Insulin unit")

    var body: some View {
        List {
            Section {
                Text(LocalizedString(
                    "This method of refilling is only intended for when the pump cannot provide a way to refill the reservoir or prime the cannula",
                    comment: "Label for warning refill"
                ))
            } header: {
                Label(
                    LocalizedString("WARNING: USE WITH CAUTION!", comment: "Title for warning refill"),
                    systemImage: "exclamationmark.triangle.fill"
                )
            }

            if !viewModel.cannulaOnly {
                Section {
                    HStack {
                        Text(LocalizedString("Reservoir amount", comment: "Label for reservoir refilled amount"))
                        Spacer()
                        Text(String(viewModel.reservoirAmount) + self.unitText)
                    }
                    .foregroundColor(isEditingReservoirAmount ? Color.blue : Color.primary)
                    .onTapGesture {
                        withAnimation {
                            self.isEditingReservoirAmount.toggle()
                        }
                    }

                    if self.isEditingReservoirAmount {
                        ResizeablePicker(
                            selection: $viewModel.reservoirAmount,
                            data: Array(0 ... 60).map({ $0 * 5 }),
                            formatter: { value in "\(value)\(self.unitText)" }
                        )
                        .padding(.horizontal)
                    }

                    if viewModel.failedReservoirAmount {
                        Label(
                            LocalizedString(
                                "Failed to set reservoir amount. Re-sync pump data and try again please",
                                comment: "Label for error first step refill"
                            ),
                            systemImage: "exclamationmark.circle.fill"
                        )
                        .foregroundStyle(.red)
                        .transition(.move(edge: .top))
                    }

                    SaveButton(loading: $viewModel.loadingReservoirAmount) {
                        viewModel.setReservoirAmount()
                    }
                } header: {
                    Text(LocalizedString("Step 1: Set reservoir level", comment: "Label for first step refill"))
                }
            }

            if $viewModel.currentStep.wrappedValue.rawValue >= RefillSteps.tube.rawValue && !viewModel.cannulaOnly {
                Section {
                    HStack {
                        Text(LocalizedString("Tube refill amount", comment: "Label for tube refilled amount"))
                            .foregroundColor(Color.primary)
                        Spacer()
                        Text(String(viewModel.tubeAmount) + self.unitText)
                    }
                    .onTapGesture {
                        withAnimation {
                            self.isEditingTubeRefillAmount.toggle()
                        }
                    }

                    if self.isEditingTubeRefillAmount {
                        ResizeablePicker(
                            selection: $viewModel.tubeAmount,
                            data: Array(0 ... 150).map({ Double($0) / 10 }),
                            formatter: { value in "\(value)\(self.unitText)" }
                        )
                        .padding(.horizontal)
                    }

                    if viewModel.failedTubeAmount {
                        Label(
                            LocalizedString(
                                "Failed to prime the tube. Please try again later",
                                comment: "Label for error second step refill"
                            ),
                            systemImage: "exclamationmark.circle.fill"
                        )
                        .foregroundStyle(.red)
                        .transition(.move(edge: .top))
                    }

                    if viewModel.loadingTubeAmount || viewModel.currentStep.rawValue > RefillSteps.tube.rawValue {
                        ProgressView(value: $viewModel.tubeProgress.wrappedValue) {
                            Text(
                                "\(String(format: "%.1f", viewModel.tubeDeliveredUnits))\(self.unitText) / \(String(format: "%.1f", viewModel.tubeAmount))\(self.unitText)"
                            )
                        }
                    }

                    SaveButton(loading: $viewModel.loadingTubeAmount) {
                        viewModel.primeTube()
                    }
                } header: {
                    Text(LocalizedString("Step 2: Set tube refill amount", comment: "Label for second step refill"))
                }
                .transition(.move(edge: .top))
            }

            if $viewModel.currentStep.wrappedValue.rawValue >= RefillSteps.prime.rawValue || viewModel.cannulaOnly {
                Section {
                    HStack {
                        Text(LocalizedString("Prime amount", comment: "Label for tube refilled amount"))
                            .foregroundColor(Color.primary)
                        Spacer()
                        Text(String(viewModel.primeAmount) + self.unitText)
                    }
                    .onTapGesture {
                        withAnimation {
                            self.isEditingPrimeRefillAmount.toggle()
                        }
                    }

                    if self.isEditingPrimeRefillAmount {
                        ResizeablePicker(
                            selection: $viewModel.primeAmount,
                            data: Array(0 ... 20).map({ Double($0) / 10 }),
                            formatter: { value in "\(value)\(self.unitText)" }
                        )
                        .padding(.horizontal)
                    }

                    if viewModel.failedPrimeAmount {
                        Label(
                            LocalizedString(
                                "Failed to prime the cannula. Please try again later",
                                comment: "Label for error third step refill"
                            ),
                            systemImage: "exclamationmark.circle.fill"
                        )
                        .foregroundStyle(.red)
                        .transition(.move(edge: .top))
                    }

                    if viewModel.loadingPrimeAmount || viewModel.currentStep.rawValue > RefillSteps.prime.rawValue {
                        ProgressView(value: $viewModel.primeProgress.wrappedValue) {
                            Text(
                                "\(String(format: "%.1f", viewModel.primeDeliveredUnits))\(self.unitText) / \(String(format: "%.1f", viewModel.primeAmount))\(self.unitText)"
                            )
                        }
                    }

                    SaveButton(loading: $viewModel.loadingPrimeAmount) {
                        viewModel.primeCannula()
                    }
                } header: {
                    Text(LocalizedString(
                        viewModel.cannulaOnly ? "Step 1: Prime cannula" : "Step 3: Prime cannula",
                        comment: "Label for third step refill"
                    ))
                }
                .transition(.move(edge: .top))
            }
        }
        .edgesIgnoringSafeArea(.bottom)
        .navigationBarHidden(false)
        .navigationBarTitle(LocalizedString(
            viewModel.cannulaOnly ? "Cannula refill" : "Reservoir/cannula refill",
            comment: "Title for reservoir/cannula refill"
        ))
    }
}

struct SaveButton: View {
    var text = LocalizedString("Save", comment: "Text for continue button")
    var loading: Binding<Bool> = .constant(false)
    var disabled: Binding<Bool> = .constant(false)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if loading.wrappedValue {
                ActivityIndicator(isAnimating: .constant(true), style: .medium)
            } else {
                Text(text)
            }
        }
        .disabled(loading.wrappedValue || disabled.wrappedValue)
    }
}
