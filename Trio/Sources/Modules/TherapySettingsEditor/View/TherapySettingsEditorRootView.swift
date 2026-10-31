import SwiftUI
import Swinject

extension TherapySettingsEditor {
    struct RootView: BaseView {
        let resolver: Resolver
        let therapyType: TherapyType
        @State var state: StateModel

        @Namespace private var bottomID

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        init(
            resolver: Resolver,
            therapyType: TherapyType
        ) {
            self.resolver = resolver
            self.therapyType = therapyType
            state = StateModel(therapyType)
        }

        var body: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack {
                        TherapySettingsEditor.EditingView(
                            therapyType: therapyType,
                            items: $state.items,
                            unit: state.unit,
                            timeOptions: state.timeOptions,
                            valueOptions: state.valueOptions,
                            validateOnDelete: state.validate,
                            onItemAdded: {
                                withAnimation {
                                    proxy.scrollTo(bottomID, anchor: .bottom)
                                }
                            },
                            total: state.total
                        )
                        .padding(.horizontal)
                    }
                    .id(bottomID)
                    .padding(.bottom, 70)
                }
                .overlay(alignment: .bottom) {
                    saveButton
                }
            }
            .onAppear {
                configureView()
                state.validate()
            }
            .alert(isPresented: $state.showAlert) {
                Alert(
                    title: Text("Unable to Save"),
                    message: Text(state.saveError!.localizedDescription),
                    dismissButton: .default(Text("Close"))
                )
            }
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationBarTitleDisplayMode(.automatic)
            .navigationTitle(therapyType.title)
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
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
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
            state.isSaving || state.items.isEmpty || !state.hasChanges
        }
    }
}
