import Charts
import SwiftUI
import Swinject

extension TargetsEditor {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @Namespace private var bottomID

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var saveButton: some View {
            ZStack {
                let shouldDisableButton = state.shouldDisplaySaving || state.items.isEmpty || !state.hasChanges

                Rectangle()
                    .frame(width: UIScreen.main.bounds.width, height: 65)
                    .foregroundStyle(colorScheme == .dark ? Color.bgDarkerDarkBlue : Color.white)
                    .background(.thinMaterial)
                    .opacity(0.8)
                    .clipShape(Rectangle())

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
                            .frame(width: UIScreen.main.bounds.width * 0.9, alignment: .center)
                            .padding(10)
                        })
                            .frame(width: UIScreen.main.bounds.width * 0.9, height: 40, alignment: .center)
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
                                    },
                                    chartColor: Color.green,
                                    chartDisplayValueSelector: { state.units == .mgdL ? $0.value : $0.value.asMmolL },
                                    chartShowsArea: false,
                                    chartYScale: (state.units == .mgdL ? Decimal(72) : Decimal(72).asMmolL) ...
                                        (state.units == .mgdL ? Decimal(180) : Decimal(180).asMmolL)
                                )
                                .padding(.horizontal)
                                .id(bottomID)
                            }
                        }
                    }

                    saveButton
                }
                .background(appState.trioBackgroundColor(for: colorScheme))
                .onAppear(perform: configureView)
                .navigationTitle("Glucose Targets")
                .navigationBarTitleDisplayMode(.automatic)
                .onAppear {
                    state.validate()
                    state.therapyItems = state.getTherapyItems()
                }
                .onChange(of: state.therapyItems) { _, newItems in
                    state.updateFromTherapyItems(newItems)
                }
            }
        }
    }
}
