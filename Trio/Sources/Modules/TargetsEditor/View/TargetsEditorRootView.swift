import SwiftUI
import Swinject

extension TargetsEditor {
    struct RootView: BaseView {
        let resolver: Resolver
        /// A stored profile to edit; nil edits the live settings.
        var profileName: String? = nil
        @StateObject var state = StateModel()
        @State private var refreshUI = UUID()
        @Namespace private var bottomID

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var saveButton: some View {
            ZStack {
                let shouldDisableButton = state.shouldDisplaySaving || state.items.isEmpty || !state.hasChanges

                Rectangle()
                    .frame(height: 65)
                    .foregroundStyle(colorScheme == .dark ? Color.bgDarkerDarkBlue : Color.white)
                    .background(.thinMaterial)
                    .opacity(0.8)
                    .clipShape(Rectangle())
                    .ignoresSafeArea(edges: .horizontal)

                Group {
                    HStack {
                        Button(action: {
                            let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                            impactHeavy.impactOccurred()
                            state.save()

                            // deactivate saving display after 1.25 seconds
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
                                state.shouldDisplaySaving = false
                            }
                        }, label: {
                            HStack {
                                if state.shouldDisplaySaving {
                                    ProgressView().padding(.trailing, 10)
                                }
                                Text(state.shouldDisplaySaving ? "Saving..." : "Save")
                            }
                            .containerRelativeFrame(.horizontal) { width, _ in width * 0.9 }
                            .padding(10)
                        })
                            .containerRelativeFrame(.horizontal) { width, _ in width * 0.9 }
                            .frame(height: 40)
                            .disabled(shouldDisableButton)
                            .background(shouldDisableButton ? Color(.systemGray4) : Color(.systemBlue))
                            .tint(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }.padding(5)
            }
        }

        var body: some View {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    ScrollView {
                        LazyVStack {
                            VStack(alignment: .leading, spacing: 0) {
                                if let bannerInfo = state.bannerInfo {
                                    TherapyProfileBanner(info: bannerInfo)
                                }

                                // Chart visualization
                                if !state.items.isEmpty {
                                    glucoseTargetChart
                                        .frame(height: 180)
                                        .padding()
                                        .background(Color.chart.opacity(0.65))
                                        .clipShape(
                                            .rect(
                                                topLeadingRadius: 10,
                                                bottomLeadingRadius: 0,
                                                bottomTrailingRadius: 0,
                                                topTrailingRadius: 10
                                            )
                                        )
                                        .padding(.horizontal)
                                        .padding(.top)
                                }

                                // Glucose target list
                                TherapySettingEditorView(
                                    items: $state.therapyItems,
                                    unit: state.units == .mgdL ? .mgdL : .mmolL,
                                    timeOptions: state.timeValues,
                                    valueOptions: state.rateValues,
                                    validateOnDelete: state.validate,
                                    onItemAdded: {
                                        withAnimation {
                                            proxy.scrollTo(bottomID, anchor: .bottom)
                                        }
                                    }
                                )
                                .padding(.horizontal)
                                .id(bottomID)

                                HStack {
                                    Image(systemName: "hand.draw.fill")
                                        .padding(.leading)

                                    Text("Swipe to delete a single entry. Tap on it, to edit its time or value.")
                                        .padding(.trailing)
                                }
                                .font(.subheadline)
                                .fontWeight(.light)
                                .foregroundStyle(.secondary)
                                .padding()
                            }
                        }
                    }

                    saveButton
                        .alert(
                            "Unable to Save",
                            isPresented: Binding(
                                get: { state.profileSaveError != nil },
                                set: { if !$0 { state.profileSaveError = nil } }
                            )
                        ) {
                            Button("OK", role: .cancel) {}
                        } message: {
                            Text(state.profileSaveError ?? "")
                        }
                }
                .background(appState.trioBackgroundColor(for: colorScheme))
                .onAppear { configureView { state.profileName = profileName } }
                .navigationTitle("Glucose Targets")
                .navigationBarTitleDisplayMode(.automatic)
                .onAppear {
                    state.validate()
                    state.therapyItems = state.getTherapyItems()
                }
                .onChange(of: state.therapyItems) { _, newItems in
                    state.updateFromTherapyItems(newItems)
                    refreshUI = UUID()
                }
            }
        }

        // Chart for visualizing glucose targets
        private var glucoseTargetChart: some View {
            TherapyProfileChart(
                entries: state.items.map {
                    let value = state.rateValues[$0.lowIndex]
                    return TherapyProfileChart.Entry(
                        start: state.timeValues[$0.timeIndex],
                        value: state.units == .mgdL ? value : value.asMmolL
                    )
                },
                color: .green,
                fillsArea: false,
                lineWidth: 2.5,
                yDomain: (state.units == .mgdL ? Decimal(72) : Decimal(72).asMmolL) ...
                    (state.units == .mgdL ? Decimal(180) : Decimal(180).asMmolL),
                accessibilityLabel: Text("Glucose target profile chart, 24 hours")
            )
            .id(refreshUI) // Force chart update
        }
    }
}
