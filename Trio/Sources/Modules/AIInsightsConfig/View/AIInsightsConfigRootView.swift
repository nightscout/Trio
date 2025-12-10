import SwiftUI
import Swinject

extension AIInsightsConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            Form {
                Section {
                    HStack {
                        Image(systemName: state.isAPIKeyConfigured ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(state.isAPIKeyConfigured ? .green : .orange)
                        Text(state.isAPIKeyConfigured
                            ? "API key configured. Ready to analyze your data."
                            : "Configure your Claude API key to get started.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                .listRowBackground(Color.chart)

                Section(
                    header: Text("Analysis Tools"),
                    content: {
                        NavigationLink(destination: QuickAnalysisView(state: state)) {
                            HStack {
                                Image(systemName: "bolt.fill")
                                    .foregroundColor(.yellow)
                                VStack(alignment: .leading) {
                                    Text("Quick Analysis")
                                        .font(.headline)
                                    Text("Instant insights from last 7 days")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        NavigationLink(destination: AskClaudeView(state: state)) {
                            HStack {
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                    .foregroundColor(.blue)
                                VStack(alignment: .leading) {
                                    Text("Ask Claude")
                                        .font(.headline)
                                    Text("Chat about your data")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        NavigationLink(destination: WeeklyReportView(state: state)) {
                            HStack {
                                Image(systemName: "doc.text.fill")
                                    .foregroundColor(.green)
                                VStack(alignment: .leading) {
                                    Text("Weekly Report")
                                        .font(.headline)
                                    Text("Comprehensive analysis to share")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                )
                .listRowBackground(Color.chart)

                Section(
                    header: Text("Configuration"),
                    footer: Text("Your Claude API key is stored securely in the iOS Keychain.")
                ) {
                    NavigationLink(destination: APIKeySettingsView(state: state)) {
                        HStack {
                            Image(systemName: "key.fill")
                                .foregroundColor(.orange)
                            Text("API Key Settings")
                            Spacer()
                            if state.isAPIKeyConfigured {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                }
                .listRowBackground(Color.chart)
            }
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("AI Analysis")
            .navigationBarTitleDisplayMode(.automatic)
            .onAppear(perform: configureView)
        }
    }

    // MARK: - Quick Analysis View

    struct QuickAnalysisView: View {
        @ObservedObject var state: StateModel
        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            ScrollView {
                VStack(spacing: 20) {
                    if state.quickAnalysisResult.isEmpty && !state.isAnalyzing {
                        // Initial state
                        VStack(spacing: 16) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.yellow)

                            Text("Quick Analysis")
                                .font(.title2)
                                .fontWeight(.bold)

                            Text("Get instant AI-powered insights about your last 7 days of glucose data.")
                                .multilineTextAlignment(.center)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)

                            Button(action: {
                                Task {
                                    await state.runQuickAnalysis()
                                }
                            }) {
                                HStack {
                                    Image(systemName: "sparkles")
                                    Text("Analyze My Data")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(state.isAPIKeyConfigured ? Color.accentColor : Color.gray)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            .disabled(!state.isAPIKeyConfigured)
                            .padding(.horizontal)

                            if !state.isAPIKeyConfigured {
                                Text("Please configure your API key first")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(.top, 40)
                    }

                    if state.isAnalyzing {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Analyzing your data...")
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 60)
                    }

                    if let error = state.analysisError {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.red)
                            Text(error)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)

                            Button("Try Again") {
                                Task {
                                    await state.runQuickAnalysis()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                    }

                    if !state.quickAnalysisResult.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Analysis Complete")
                                    .font(.headline)
                            }

                            Text(state.quickAnalysisResult)
                                .font(.body)
                                .padding()
                                .background(Color.chart)
                                .cornerRadius(12)

                            Button(action: {
                                Task {
                                    await state.runQuickAnalysis()
                                }
                            }) {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Run Again")
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                    }

                    Spacer()
                }
            }
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Quick Analysis")
        }
    }

    // MARK: - Ask Claude View

    struct AskClaudeView: View {
        @ObservedObject var state: StateModel
        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState
        @FocusState private var isInputFocused: Bool

        var body: some View {
            VStack(spacing: 0) {
                if state.chatMessages.isEmpty {
                    // Empty state
                    VStack(spacing: 16) {
                        Spacer()

                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.blue)

                        Text("Ask Claude")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Ask questions about your glucose data. Claude will analyze your last 7 days and answer based on your patterns.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Example questions:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            ForEach(["Why am I high in the morning?", "Are my carb ratios working?", "When do I tend to go low?"], id: \.self) { example in
                                Button(action: {
                                    state.currentMessage = example
                                }) {
                                    Text(example)
                                        .font(.caption)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.chart)
                                        .cornerRadius(16)
                                }
                            }
                        }
                        .padding(.top)

                        Spacer()
                    }
                    .padding()
                } else {
                    // Chat messages
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(state.chatMessages) { message in
                                    ChatBubble(message: message)
                                        .id(message.id)
                                }

                                if state.isSendingMessage {
                                    HStack {
                                        ProgressView()
                                            .padding(.horizontal)
                                        Text("Claude is thinking...")
                                            .foregroundColor(.secondary)
                                            .font(.caption)
                                    }
                                    .padding(.vertical, 8)
                                }
                            }
                            .padding()
                        }
                        .onChange(of: state.chatMessages.count) { _, _ in
                            if let lastMessage = state.chatMessages.last {
                                withAnimation {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }

                // Input area
                VStack(spacing: 0) {
                    Divider()
                    HStack(spacing: 12) {
                        TextField("Ask about your data...", text: $state.currentMessage, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(1 ... 4)
                            .focused($isInputFocused)
                            .disabled(!state.isAPIKeyConfigured)

                        Button(action: {
                            Task {
                                await state.sendChatMessage()
                            }
                        }) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(
                                    state.currentMessage.isEmpty || state.isSendingMessage || !state.isAPIKeyConfigured
                                        ? .gray : .accentColor
                                )
                        }
                        .disabled(state.currentMessage.isEmpty || state.isSendingMessage || !state.isAPIKeyConfigured)
                    }
                    .padding()
                    .background(Color.chart)
                }
            }
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Ask Claude")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !state.chatMessages.isEmpty {
                        Button("Clear") {
                            state.clearChat()
                        }
                    }
                }
            }
        }
    }

    struct ChatBubble: View {
        let message: ChatMessage

        var body: some View {
            HStack {
                if message.isUser { Spacer() }

                VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                    Text(message.content)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(message.isUser ? Color.accentColor : Color.chart)
                        .foregroundColor(message.isUser ? .white : .primary)
                        .cornerRadius(16)

                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: message.isUser ? .trailing : .leading)

                if !message.isUser { Spacer() }
            }
        }
    }

    // MARK: - Weekly Report View

    struct WeeklyReportView: View {
        @ObservedObject var state: StateModel
        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState
        @State private var showShareSheet = false

        var body: some View {
            ScrollView {
                VStack(spacing: 20) {
                    if state.weeklyReport.isEmpty && !state.isGeneratingReport {
                        // Initial state
                        VStack(spacing: 16) {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.green)

                            Text("Weekly Report")
                                .font(.title2)
                                .fontWeight(.bold)

                            Text("Generate a comprehensive analysis of your last 7 days. Includes statistics, patterns, and recommendations to discuss with your healthcare provider.")
                                .multilineTextAlignment(.center)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)

                            Button(action: {
                                Task {
                                    await state.generateWeeklyReport()
                                }
                            }) {
                                HStack {
                                    Image(systemName: "doc.badge.gearshape")
                                    Text("Generate Report")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(state.isAPIKeyConfigured ? Color.green : Color.gray)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            .disabled(!state.isAPIKeyConfigured)
                            .padding(.horizontal)

                            if !state.isAPIKeyConfigured {
                                Text("Please configure your API key first")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(.top, 40)
                    }

                    if state.isGeneratingReport {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Generating your weekly report...")
                                .foregroundColor(.secondary)
                            Text("This may take a moment")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 60)
                    }

                    if let error = state.analysisError, state.weeklyReport.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.red)
                            Text(error)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)

                            Button("Try Again") {
                                Task {
                                    await state.generateWeeklyReport()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                    }

                    if !state.weeklyReport.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Report Generated")
                                    .font(.headline)
                                Spacer()
                                Button(action: {
                                    showShareSheet = true
                                }) {
                                    Image(systemName: "square.and.arrow.up")
                                }
                            }

                            Text(state.weeklyReport)
                                .font(.body)
                                .padding()
                                .background(Color.chart)
                                .cornerRadius(12)

                            HStack {
                                Button(action: {
                                    Task {
                                        await state.generateWeeklyReport()
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "arrow.clockwise")
                                        Text("Regenerate")
                                    }
                                }
                                .buttonStyle(.bordered)

                                Spacer()

                                Button(action: {
                                    showShareSheet = true
                                }) {
                                    HStack {
                                        Image(systemName: "square.and.arrow.up")
                                        Text("Share")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding()
                    }

                    Spacer()
                }
            }
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Weekly Report")
            .sheet(isPresented: $showShareSheet) {
                AIInsightsShareSheet(activityItems: [state.getShareableReport()])
            }
        }
    }

    // MARK: - API Key Settings View

    struct APIKeySettingsView: View {
        @ObservedObject var state: StateModel
        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState
        @State private var showDeleteConfirmation = false

        var body: some View {
            Form {
                Section(
                    header: Text("Claude API Key"),
                    footer: Text("Get your API key from console.anthropic.com. Your key is stored securely in the iOS Keychain and never sent anywhere except to Claude's API.")
                ) {
                    HStack {
                        if state.isAPIKeyVisible {
                            TextField("sk-ant-...", text: $state.apiKey)
                                .textContentType(.password)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        } else {
                            SecureField("sk-ant-...", text: $state.apiKey)
                                .textContentType(.password)
                        }

                        Button(action: {
                            state.toggleAPIKeyVisibility()
                        }) {
                            Image(systemName: state.isAPIKeyVisible ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                    }

                    Button(action: {
                        state.saveAPIKey()
                    }) {
                        HStack {
                            Image(systemName: "checkmark.circle")
                            Text("Save API Key")
                        }
                    }
                    .disabled(state.apiKey.isEmpty)
                }
                .listRowBackground(Color.chart)

                if state.isAPIKeyConfigured {
                    Section {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("API Key Configured")
                                .foregroundColor(.green)
                        }

                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete API Key")
                            }
                        }
                    }
                    .listRowBackground(Color.chart)
                }

                Section(
                    header: Text("About"),
                    footer: Text("Claude is Anthropic's AI assistant. API usage is billed to your Anthropic account.")
                ) {
                    SwiftUI.Link(destination: URL(string: "https://console.anthropic.com")!) {
                        HStack {
                            Text("Get API Key")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.secondary)
                        }
                    }

                    SwiftUI.Link(destination: URL(string: "https://www.anthropic.com/pricing")!) {
                        HStack {
                            Text("View Pricing")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .listRowBackground(Color.chart)
            }
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("API Key Settings")
            .alert("Delete API Key?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    state.deleteAPIKey()
                }
            } message: {
                Text("This will remove your API key from the device. You can add a new one later.")
            }
        }
    }
    // MARK: - Share Sheet for AI Insights

    struct AIInsightsShareSheet: UIViewControllerRepresentable {
        let activityItems: [Any]

        func makeUIViewController(context: Context) -> UIActivityViewController {
            UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        }

        func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
    }
}
