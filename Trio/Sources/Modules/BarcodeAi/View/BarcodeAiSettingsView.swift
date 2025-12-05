import SwiftUI
import Swinject

extension BarcodeAi {
    struct SettingsView: BaseView {
        let resolver: Resolver
        @StateObject var state = SettingsStateModel()

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            List {
                Section(
                    header: Text("API Key"),
                    content: {
                        SecureField("Gemini API Key", text: $state.apiKey)
                            .disableAutocorrection(true)
                            .autocapitalization(.none)
                            .textContentType(.password)
                            .keyboardType(.asciiCapable)

                        if state.message.isNotEmpty {
                            Text(state.message)
                                .foregroundStyle(state.message.hasPrefix("Error:") ? .red : .green)
                        }

                        Button {
                            state.save()
                        } label: {
                            Text("Save API Key")
                                .font(.title3)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .buttonStyle(.bordered)
                        .disabled(state.apiKey.isEmpty)

                        if state.hasApiKey {
                            Button(role: .destructive) {
                                state.delete()
                            } label: {
                                Text("Remove API Key")
                                    .font(.title3)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .buttonStyle(.bordered)
                            .tint(Color.loopRed)
                        }
                    }
                )
                .listRowBackground(Color.chart)

                // Model Selection Section
                if state.hasApiKey {
                    Section(
                        header: HStack {
                            Text("AI Model")
                            if state.isLoadingModels {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .padding(.leading, 4)
                            }
                        },
                        footer: Text(
                            "Select the Gemini model to use for food analysis. Newer models are generally more accurate but may be slower."
                        )
                    ) {
                        Picker("Model", selection: $state.selectedModelId) {
                            ForEach(state.availableModels) { model in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.displayName)
                                        .font(.body)
                                }
                                .tag(model.id)
                            }
                        }
                        .pickerStyle(.navigationLink)
                        .onChange(of: state.selectedModelId) { _, newValue in
                            state.selectModel(newValue)
                        }

                        Button {
                            state.fetchAvailableModels()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Refresh Models")
                            }
                        }
                        .disabled(state.isLoadingModels)
                    }
                    .listRowBackground(Color.chart)
                }

                Section(
                    footer: Text(
                        "Enter your Gemini API key to enable AI-powered image analysis for nutrition estimation. You can get an API key from Google AI Studio."
                    )
                ) {
                    EmptyView()
                }
                .listRowBackground(Color.chart)
            }
            .listSectionSpacing(sectionSpacing)
            .navigationTitle("AI Settings")
            .navigationBarTitleDisplayMode(.automatic)
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear {
                configureView {
                    if state.hasApiKey {
                        state.fetchAvailableModels()
                    }
                }
            }
        }
    }
}
