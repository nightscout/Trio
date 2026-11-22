import SwiftUI
import Swinject

extension BasalProfileEditor {
    struct RootView: BaseView {
        let resolver: Resolver
        /// A stored profile to edit; nil edits the live settings.
        var profileName: String? = nil
        @State var state = StateModel()
        @State private var refreshUI = UUID()
        @Namespace private var bottomID

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        private var rateFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter
        }

        // Chart for visualizing basal profile
        private var basalProfileChart: some View {
            TherapyProfileChart(
                entries: state.items.map {
                    TherapyProfileChart.Entry(start: state.timeValues[$0.timeIndex], value: state.rateValues[$0.rateIndex])
                },
                color: .purple,
                accessibilityLabel: Text("Basal rate profile chart, 24 hours")
            )
            .id(refreshUI) // Force chart update
        }

        var saveButton: some View {
            ZStack {
                let shouldDisableButton = state.syncInProgress || state.items.isEmpty || !state.hasChanges

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
                        }, label: {
                            HStack {
                                if state.syncInProgress {
                                    ProgressView().padding(.trailing, 10)
                                }
                                Text(state.syncInProgress ? "Saving..." : "Save")
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

        var fullScheduleWarning: some View {
            VStack {
                Text(
                    "Basal profile covers 24 hours. You cannot add more rates. Please remove or adjust existing rates to make space."
                ).bold()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.tabBar)
            .clipShape(
                .rect(
                    topLeadingRadius: 10,
                    bottomLeadingRadius: 10,
                    bottomTrailingRadius: 10,
                    topTrailingRadius: 10
                )
            )
        }

        var unsupportedRatesWarning: some View {
            Text(
                "Some basal rates of this schedule are above the max basal rate or are not rates your pump supports. Each is shown as the nearest rate that can be saved. Check them before you save."
            )
            .bold()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.tabBar)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }

        var totalBasalRow: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Total")
                        .bold()

                    Spacer()

                    HStack {
                        Text(rateFormatter.string(from: state.total as NSNumber) ?? "0")
                        Text("U/day")
                            .foregroundStyle(Color.secondary)
                    }
                    .id(refreshUI)
                }
            }
            .padding()
            .background(Color.chart.opacity(0.65))
            .cornerRadius(10)
            .padding(.horizontal)
            .id(bottomID)
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

                                if state.hasUnsupportedRates {
                                    unsupportedRatesWarning
                                        .padding()
                                }

                                if !state.canAdd {
                                    fullScheduleWarning
                                        .padding()
                                }

                                // Chart visualization
                                if !state.items.isEmpty {
                                    basalProfileChart
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

                                // Basal profile list
                                TherapySettingEditorView(
                                    items: $state.therapyItems,
                                    unit: .unitPerHour,
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

                                if !state.items.isEmpty {
                                    totalBasalRow
                                }

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
                .alert(isPresented: $state.showAlert) {
                    Alert(
                        title: Text("Unable to Save"),
                        message: Text("Trio could not communicate with your pump. Changes to your basal profile were not saved."),
                        dismissButton: .default(Text("Close"))
                    )
                }
                .navigationTitle("Basal Rates")
                .navigationBarTitleDisplayMode(.automatic)
                .onAppear {
                    configureView { state.profileName = profileName }
                    state.validate()
                    state.therapyItems = state.getTherapyItems()
                }
                .onChange(of: state.therapyItems) { _, newItems in
                    state.updateFromTherapyItems(newItems)
                    state.calcTotal()
                    refreshUI = UUID()
                }
            }
        }
    }
}
