import SwiftUI
import Swinject

extension BarcodeScannerSettings {
    struct RootView: BaseView {
        let resolver: Resolver

        @State var state = StateModel()

        @State private var showDeleteConfirmation = false
        @State private var customURL: String = ""
        @State private var showURLInput = false
        @State private var shouldDisplayHint = false
        @State private var hintDetent = PresentationDetent.medium
        @State private var selectedVerboseHint: AnyView?
        @State private var hintLabel: String = ""

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        // Default GitHub URL for the model
        private let defaultModelURL =
            "https://github.com/EJM0/recompiled-openfoodfacts-extractor/releases/download/1/nutrition_extractor.mlpackage.zip"

        var body: some View {
            List {
                // MARK: - Enable/Disable Section

                Section(
                    header: Text("AI Nutrition Scanner"),
                    content: {
                        Toggle(isOn: $state.useAINutritionScanner) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Enable AI Label Scanner")
                                Text("Show the Analyze Label button in the Food Scanner")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onChange(of: state.useAINutritionScanner) { _, newValue in
                            state.updateAINutritionScannerSetting(newValue)
                        }
                    }
                ).listRowBackground(Color.chart)

                // Only show model-related sections if AI scanner is enabled
                if state.useAINutritionScanner {
                    // MARK: - Model Status Section

                    Section(
                        header: Text("AI Model Status"),
                        content: {
                            modelStatusRow
                        }
                    ).listRowBackground(Color.chart)

                    // MARK: - Download Section

                    if case .notDownloaded = state.modelManager.state {
                        Section(
                            header: Text("Download"),
                            content: {
                                VStack {
                                    Button {
                                        Task {
                                            await state.downloadModel(from: downloadURL)
                                        }
                                    } label: {
                                        Text("Download AI Model")
                                            .font(.title3)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .buttonStyle(.bordered)

                                    HStack(alignment: .center) {
                                        Text("Download the nutrition label extraction model (~350 MB)")
                                            .font(.footnote)
                                            .foregroundColor(.secondary)
                                            .lineLimit(nil)
                                        Spacer()
                                        Button {
                                            hintLabel = String(localized: "AI Model Download")
                                            selectedVerboseHint = AnyView(
                                                VStack(alignment: .leading, spacing: 12) {
                                                    Text(
                                                        "The AI model enables automatic extraction of nutritional values from food labels using your device's camera."
                                                    )
                                                    Text(
                                                        "The model is based on the Open Food Facts nutrition extractor, which is open source and trained on nutrition labels from around the world."
                                                    )
                                                    Text(
                                                        "The model will be stored locally on your device and requires approximately 350 MB of storage."
                                                    )
                                                }
                                            )
                                            shouldDisplayHint.toggle()
                                        } label: {
                                            Image(systemName: "questionmark.circle")
                                        }
                                        .buttonStyle(BorderlessButtonStyle())
                                    }
                                    .padding(.top)
                                }
                                .padding(.vertical)

                                Toggle("Use Custom URL", isOn: $showURLInput)

                                if showURLInput {
                                    TextField("https://github.com/.../model.tar", text: $customURL)
                                        .disableAutocorrection(true)
                                        .textContentType(.URL)
                                        .autocapitalization(.none)
                                        .keyboardType(.URL)
                                }
                            }
                        ).listRowBackground(Color.chart)
                    }

                    // MARK: - Downloading Progress Section

                    if case let .downloading(progress) = state.modelManager.state {
                        Section(
                            header: Text("Downloading"),
                            content: {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("Downloading model...")
                                        Spacer()
                                        Text("\(Int(progress * 100))%")
                                            .foregroundStyle(.secondary)
                                    }
                                    ProgressView(value: progress)
                                        .tint(.insulin)

                                    Button(role: .destructive) {
                                        state.cancelDownload()
                                    } label: {
                                        Text("Cancel Download")
                                            .font(.title3)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .buttonStyle(.bordered)
                                    .tint(.loopRed)
                                }
                                .padding(.vertical)
                            }
                        ).listRowBackground(Color.chart)
                    }

                    // MARK: - Load Model Section

                    if case .downloaded = state.modelManager.state {
                        Section(
                            header: Text("Load Model"),
                            content: {
                                VStack {
                                    Button {
                                        Task {
                                            await state.loadModel()
                                        }
                                    } label: {
                                        Text("Load AI Model")
                                            .font(.title3)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .buttonStyle(.bordered)

                                    HStack(alignment: .center) {
                                        Text("Load the model into memory to enable nutrition label scanning")
                                            .font(.footnote)
                                            .foregroundColor(.secondary)
                                            .lineLimit(nil)
                                        Spacer()
                                    }
                                    .padding(.top)
                                }
                                .padding(.vertical)
                            }
                        ).listRowBackground(Color.chart)
                    }

                    // MARK: - Loading Section

                    if case .loading = state.modelManager.state {
                        Section(
                            content: {
                                HStack {
                                    Text("Loading model...")
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        ).listRowBackground(Color.chart)
                    }

                    // MARK: - Delete Section

                    if case .ready = state.modelManager.state {
                        Section(
                            content: {
                                VStack {
                                    Button(role: .destructive) {
                                        showDeleteConfirmation = true
                                    } label: {
                                        Text("Delete AI Model")
                                            .font(.title3)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .buttonStyle(.bordered)
                                    .tint(.loopRed)

                                    HStack(alignment: .center) {
                                        Text("Remove the AI model to free up storage space")
                                            .font(.footnote)
                                            .foregroundColor(.secondary)
                                            .lineLimit(nil)
                                        Spacer()
                                    }
                                    .padding(.top)
                                }
                                .padding(.vertical)
                            }
                        ).listRowBackground(Color.chart)
                    }

                    // MARK: - Error Section

                    if case let .error(message) = state.modelManager.state {
                        Section(
                            header: Text("Error"),
                            content: {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(Color.loopRed)
                                        Text(message)
                                            .foregroundStyle(.secondary)
                                    }

                                    Button {
                                        Task {
                                            await state.downloadModel(from: downloadURL)
                                        }
                                    } label: {
                                        Text("Try Again")
                                            .font(.title3)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .buttonStyle(.bordered)
                                }
                                .padding(.vertical)
                            }
                        ).listRowBackground(Color.chart)
                    }

                    // MARK: - Storage Location Section

                    if state.modelManager.state != .notDownloaded {
                        Section(
                            header: Text("Storage"),
                            content: {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "folder.fill")
                                            .foregroundStyle(Color.insulin)
                                        Text("Files App Location")
                                            .font(.headline)
                                    }

                                    Text("On My iPhone → Trio → NutritionExtractor")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)

                                    HStack(alignment: .center) {
                                        Text("You can access and manage the model files directly through the Files app.")
                                            .font(.footnote)
                                            .foregroundColor(.secondary)
                                            .lineLimit(nil)
                                        Spacer()
                                        Button {
                                            hintLabel = String(localized: "Files App Access")
                                            selectedVerboseHint = AnyView(
                                                VStack(alignment: .leading, spacing: 12) {
                                                    Text(
                                                        "The AI model is stored in the Trio app's document folder, which is accessible via the iOS Files app."
                                                    )
                                                    Text("To find the model files:")
                                                    VStack(alignment: .leading, spacing: 4) {
                                                        Text("1. Open the Files app")
                                                        Text("2. Tap 'On My iPhone' (or 'On My iPad')")
                                                        Text("3. Open the 'Trio' folder")
                                                        Text("4. Find the 'NutritionExtractor' folder")
                                                    }
                                                    .font(.footnote)
                                                    Text(
                                                        "You can also import models manually by placing .mlpackage files in this folder."
                                                    )
                                                }
                                            )
                                            shouldDisplayHint.toggle()
                                        } label: {
                                            Image(systemName: "questionmark.circle")
                                        }
                                        .buttonStyle(BorderlessButtonStyle())
                                    }
                                    .padding(.top, 4)
                                }
                                .padding(.vertical, 8)
                            }
                        ).listRowBackground(Color.chart)
                    }

                    // MARK: - Information Section

                    Section(
                        header: Text("Information"),
                        content: {
                            if let url = URL(string: "https://github.com/openfoodfacts/openfoodfacts-ai") {
                                Button {
                                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                                } label: {
                                    Label("About the AI Model", systemImage: "brain")
                                        .font(.title3)
                                        .padding()
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .buttonStyle(.bordered)
                            }
                        }
                    ).listRowBackground(Color.clear)
                } // End of if useAINutritionScanner
            }
            .listSectionSpacing(sectionSpacing)
            .sheet(isPresented: $shouldDisplayHint) {
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    shouldDisplayHint: $shouldDisplayHint,
                    hintLabel: hintLabel,
                    hintText: selectedVerboseHint ?? AnyView(EmptyView()),
                    sheetTitle: String(localized: "Help", comment: "Help sheet title")
                )
            }
            .alert("Delete AI Model?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    state.deleteModel()
                }
            } message: {
                Text("This will remove the AI model from your device. You can download it again later.")
            }
            .navigationTitle("Food Scanner")
            .navigationBarTitleDisplayMode(.automatic)
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear {
                configureView()
                state.checkModelStatus()

                // Auto-load if downloaded and AI scanner is enabled
                if state.useAINutritionScanner, case .downloaded = state.modelManager.state {
                    Task {
                        await state.loadModel()
                    }
                }
            }
        }

        // MARK: - Helper Views

        private var downloadURL: String {
            if showURLInput, !customURL.isEmpty {
                return customURL
            }
            return defaultModelURL
        }

        @ViewBuilder private var modelStatusRow: some View {
            HStack {
                switch state.modelManager.state {
                case .notDownloaded:
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(.secondary)
                    Text("Not Downloaded")
                        .foregroundStyle(.secondary)

                case .downloading:
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(Color.insulin)
                    Text("Downloading...")
                        .foregroundStyle(Color.insulin)

                case .downloaded:
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.orange)
                    Text("Downloaded (not loaded)")
                        .foregroundStyle(.orange)

                case .loading:
                    Image(systemName: "gear")
                        .foregroundStyle(.secondary)
                    Text("Loading...")
                        .foregroundStyle(.secondary)

                case .ready:
                    ZStack {
                        Image(systemName: "brain")
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption2)
                            .offset(x: 9, y: 6)
                    }
                    Text("Ready")
                        .foregroundStyle(.green)

                case .error:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.loopRed)
                    Text("Error")
                        .foregroundStyle(Color.loopRed)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        BarcodeScannerSettings.RootView(resolver: TrioApp.resolver)
            .environment(AppState())
    }
}
