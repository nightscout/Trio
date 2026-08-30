import SwiftUI

extension TherapySettingsEditor {
    struct RootView<State: TherapySettingsEditor.StateModel, HeaderContent: View, FooterContent: View>: View {
        @ObservedObject var state: State
        var configureView: () -> Void
        var chartColor: Color
        var chartShowsArea: Bool
        var chartYScale: ClosedRange<Decimal>?
        @Namespace private var bottomID

        let headerContent: HeaderContent
        let footerContent: FooterContent

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        init(
            state: State,
            configureView: @escaping () -> Void,
            chartColor: Color,
            @ViewBuilder headerContent: () -> HeaderContent,
            @ViewBuilder footerContent: () -> FooterContent,
            chartShowsArea: Bool? = nil,
            chartYScale: ClosedRange<Decimal>? = nil,
        ) {
            self.state = state
            self.configureView = configureView
            self.chartColor = chartColor
            self.chartShowsArea = chartShowsArea ?? true
            self.chartYScale = chartYScale
            self.headerContent = headerContent()
            self.footerContent = footerContent()
        }

        var body: some View {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    ScrollView {
                        LazyVStack {
                            headerContent

                            TherapySettingsEditor.EditingView(
                                items: $state.therapyItems,
                                unit: state.unit,
                                timeOptions: state.timeOptions,
                                valueOptions: state.valueOptions,
                                validateOnDelete: state.validate,
                                onItemAdded: {
                                    withAnimation {
                                        proxy.scrollTo(bottomID, anchor: .bottom)
                                    }
                                },
                                chartColor: chartColor,
                                chartShowsArea: chartShowsArea,
                                chartYScale: chartYScale
                            )
                            .padding(.horizontal)

                            footerContent
                                .id(bottomID)
                        }
                        .padding(.bottom)
                    }

                    saveButton
                }
                .background(appState.trioBackgroundColor(for: colorScheme))
                .navigationBarTitleDisplayMode(.automatic)
                .onAppear {
                    configureView()
                    state.validate()
                    state.therapyItems = state.getTherapyItems()
                }
                .onChange(of: state.therapyItems) { _, newItems in
                    state.updateFromTherapyItems(newItems)
                }
            }
        }

        private var saveButton: some View {
            if #available(iOS 26.0, *) {
                return glassSaveButton
            }

            return legacySaveButton
        }

        @available(iOS 26.0, *) private var glassSaveButton: some View {
            Button(action: save) {
                saveButtonContent
                    .frame(maxWidth: .infinity)
                    .padding(5)
            }
            .disabled(shouldDisableSaveButton)
            .buttonStyle(.glassProminent)
            .padding(10)
        }

        var legacySaveButton: some View {
            ZStack {
                Rectangle()
                    .frame(width: UIScreen.main.bounds.width, height: 65)
                    .foregroundStyle(colorScheme == .dark ? Color.bgDarkerDarkBlue : Color.white)
                    .background(.thinMaterial)
                    .opacity(0.8)
                    .clipShape(Rectangle())

                Group {
                    HStack {
                        Button(action: save) {
                            saveButtonContent
                                .frame(width: UIScreen.main.bounds.width * 0.9, alignment: .center)
                                .padding(10)
                        }
                        .frame(width: UIScreen.main.bounds.width * 0.9, height: 40, alignment: .center)
                        .disabled(shouldDisableSaveButton)
                        .background(shouldDisableSaveButton ? Color(.systemGray4) : Color(.systemBlue))
                        .tint(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }.padding(5)
            }
        }

        private func save() {
            let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
            impactHeavy.impactOccurred()
            state.save()
        }

        private var saveButtonContent: some View {
            HStack {
                if state.isSaving {
                    ProgressView()
                        .padding(.trailing, 10)
                }
                Text(state.isSaving ? "Saving..." : "Save")
            }
        }

        private var shouldDisableSaveButton: Bool {
            state.isSaving || state.therapyItems.isEmpty || !state.hasChanges
        }
    }
}

extension TherapySettingsEditor.RootView where HeaderContent == EmptyView, FooterContent == EmptyView {
    init(
        state: State,
        configureView: @escaping () -> Void,
        chartColor: Color,
        chartShowsArea: Bool? = nil,
        chartYScale: ClosedRange<Decimal>? = nil,
    ) {
        self.init(
            state: state,
            configureView: configureView,
            chartColor: chartColor,
            headerContent: {
                EmptyView()
            },
            footerContent: {
                EmptyView()
            },
            chartShowsArea: chartShowsArea,
            chartYScale: chartYScale,
        )
    }
}
