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

                        NavigationLink(destination: DoctorVisitReportView(state: state)) {
                            HStack {
                                Image(systemName: "stethoscope")
                                    .foregroundColor(.purple)
                                VStack(alignment: .leading) {
                                    Text("Doctor Visit Report")
                                        .font(.headline)
                                    Text("Full export for your healthcare provider")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                )
                .listRowBackground(Color.chart)

                Section(
                    header: Text("Data Source"),
                    footer: Text(
                        state.isNightscoutAvailable
                            ? "When enabled, AI analysis uses data from Nightscout for more comprehensive history."
                            : "Configure Nightscout in Settings to enable cloud data sync."
                    )
                ) {
                    Toggle(isOn: Binding(
                        get: { state.useNightscout },
                        set: { state.toggleNightscout($0) }
                    )) {
                        HStack {
                            Image(systemName: "cloud.fill")
                                .foregroundColor(state.isNightscoutAvailable ? .green : .gray)
                            VStack(alignment: .leading) {
                                Text("Use Nightscout Data")
                                if state.isNightscoutAvailable {
                                    Text("Connected - up to 90 days of history")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                } else {
                                    Text("Not configured")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .disabled(!state.isNightscoutAvailable)
                }
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

                            if state.useNightscout && state.isNightscoutAvailable {
                                Label("Using Nightscout data", systemImage: "cloud.fill")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }

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
                            ForEach(
                                ["Why am I high in the morning?", "Are my carb ratios working?", "When do I tend to go low?"],
                                id: \.self
                            ) { example in
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

                            Text(
                                "Generate a comprehensive analysis of your last 7 days. Includes statistics, patterns, and recommendations to discuss with your healthcare provider."
                            )
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

    // MARK: - Doctor Visit Report View

    struct DoctorVisitReportView: View {
        @ObservedObject var state: StateModel
        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState
        @State private var showShareSheet = false
        @State private var showPDFShare = false

        var body: some View {
            ScrollView {
                VStack(spacing: 20) {
                    if state.doctorVisitReport.isEmpty && !state.isGeneratingDoctorReport {
                        // Initial state
                        VStack(spacing: 16) {
                            Image(systemName: "stethoscope")
                                .font(.system(size: 50))
                                .foregroundColor(.purple)

                            Text("Doctor Visit Report")
                                .font(.title2)
                                .fontWeight(.bold)

                            Text(
                                "Generate a comprehensive report for your healthcare provider. Includes all treatment settings, multi-timeframe statistics, and AI-powered pattern analysis."
                            )
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)

                            // Data source info
                            VStack(spacing: 8) {
                                if state.useNightscout && state.isNightscoutAvailable {
                                    Label("Will use up to 90 days of Nightscout data", systemImage: "cloud.fill")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                } else {
                                    Label("Will use 7 days of local app data", systemImage: "iphone")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 8)

                            // What's included
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Report includes:")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)

                                Group {
                                    Label("All treatment settings (basals, ratios, ISF, targets)", systemImage: "gearshape.fill")
                                    Label("Multi-timeframe stats (1, 3, 7, 14, 30, 90 days)", systemImage: "chart.bar.fill")
                                    Label("Time in range breakdown", systemImage: "target")
                                    Label("AI pattern analysis & recommendations", systemImage: "brain.head.profile")
                                    Label("Discussion points for your provider", systemImage: "text.bubble.fill")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color.chart.opacity(0.5))
                            .cornerRadius(12)
                            .padding(.horizontal)

                            Button(action: {
                                Task {
                                    await state.generateDoctorVisitReport()
                                }
                            }) {
                                HStack {
                                    Image(systemName: "doc.badge.gearshape")
                                    Text("Generate Doctor Report")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(state.isAPIKeyConfigured ? Color.purple : Color.gray)
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
                        .padding(.top, 20)
                    }

                    if state.isGeneratingDoctorReport {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Generating your comprehensive report...")
                                .foregroundColor(.secondary)
                            Text("Fetching historical data and analyzing patterns...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("This may take a minute")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 60)
                    }

                    if let error = state.analysisError, state.doctorVisitReport.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.red)
                            Text(error)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)

                            Button("Try Again") {
                                Task {
                                    await state.generateDoctorVisitReport()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                    }

                    if !state.doctorVisitReport.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Report Generated")
                                    .font(.headline)
                                Spacer()
                            }

                            // Data source badge
                            HStack {
                                if state.useNightscout && state.isNightscoutAvailable {
                                    Label("Nightscout Data", systemImage: "cloud.fill")
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.green.opacity(0.2))
                                        .foregroundColor(.green)
                                        .cornerRadius(8)
                                } else {
                                    Label("Local Data", systemImage: "iphone")
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.gray.opacity(0.2))
                                        .foregroundColor(.secondary)
                                        .cornerRadius(8)
                                }
                            }

                            Text(state.doctorVisitReport)
                                .font(.body)
                                .padding()
                                .background(Color.chart)
                                .cornerRadius(12)

                            // Share options
                            VStack(spacing: 12) {
                                Button(action: {
                                    showShareSheet = true
                                }) {
                                    HStack {
                                        Image(systemName: "doc.text")
                                        Text("Share as Text")
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)

                                if state.doctorReportPDFData != nil {
                                    Button(action: {
                                        showPDFShare = true
                                    }) {
                                        HStack {
                                            Image(systemName: "doc.richtext")
                                            Text("Share as PDF")
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.purple)
                                }
                            }

                            Button(action: {
                                Task {
                                    await state.generateDoctorVisitReport()
                                }
                            }) {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Regenerate Report")
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
            .navigationTitle("Doctor Visit Report")
            .sheet(isPresented: $showShareSheet) {
                AIInsightsShareSheet(activityItems: [state.getShareableDoctorReport()])
            }
            .sheet(isPresented: $showPDFShare) {
                if let pdfData = state.doctorReportPDFData {
                    AIInsightsShareSheet(activityItems: [pdfData])
                }
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
                    footer: Text(
                        "Get your API key from console.anthropic.com. Your key is stored securely in the iOS Keychain and never sent anywhere except to Claude's API."
                    )
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
