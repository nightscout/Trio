import PDFKit
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
                                    Text("Instant insights from your data")
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

                        NavigationLink(destination: PhotoCarbEstimateView(state: state, onAcceptCarbs: nil)) {
                            HStack {
                                Image(systemName: "camera.fill")
                                    .foregroundColor(.mint)
                                VStack(alignment: .leading) {
                                    Text("Estimate Carbs from Photo")
                                        .font(.headline)
                                    Text("AI-powered carb counting")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        NavigationLink(destination: ClaudeOTuneView(state: state)) {
                            HStack {
                                Image(systemName: "slider.horizontal.3")
                                    .foregroundColor(.blue)
                                VStack(alignment: .leading) {
                                    Text("Claude-o-Tune")
                                        .font(.headline)
                                    Text("AI-powered profile optimization")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                )
                .listRowBackground(Color.chart)

                // Saved Reports Section
                if !state.savedReports.isEmpty {
                    Section(
                        header: Text("Saved Reports"),
                        footer: Text("Reports are automatically saved. Tap to view or share.")
                    ) {
                        NavigationLink(destination: SavedReportsListView(state: state)) {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(.blue)
                                VStack(alignment: .leading) {
                                    Text("View Saved Reports")
                                        .font(.headline)
                                    Text("\(state.savedReports.count) report\(state.savedReports.count == 1 ? "" : "s") saved")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .listRowBackground(Color.chart)
                }

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

                    NavigationLink(destination: WhyHighLowSettingsView(state: state)) {
                        HStack {
                            Image(systemName: "exclamationmark.bubble.fill")
                                .foregroundColor(.red)
                            Text("Why High/Low Settings")
                        }
                    }

                    NavigationLink(destination: PhotoCarbSettingsView(state: state)) {
                        HStack {
                            Image(systemName: "camera.fill")
                                .foregroundColor(.mint)
                            Text("Photo Carb Settings")
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
        @State private var showShareSheet = false

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

                            Text("Get instant AI-powered insights about your glucose data.")
                                .multilineTextAlignment(.center)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)

                            // Data period info
                            Label("Analyzing last \(state.qaTimePeriod.displayName)", systemImage: "calendar")
                                .font(.caption)
                                .foregroundColor(.secondary)

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
                                Spacer()
                                Label(state.qaTimePeriod.displayName, systemImage: "calendar")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            // Rich markdown rendering
                            RichMarkdownView(content: state.quickAnalysisResult)
                                .padding()
                                .background(Color.chart)
                                .cornerRadius(12)

                            HStack {
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

                                Spacer()

                                if state.quickAnalysisPDFData != nil {
                                    Button(action: {
                                        showShareSheet = true
                                    }) {
                                        HStack {
                                            Image(systemName: "square.and.arrow.up")
                                            Text("Share PDF")
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                        }
                        .padding()
                    }

                    Spacer()
                }
            }
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Quick Analysis")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: QuickAnalysisSettingsView(state: state)) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let pdfData = state.quickAnalysisPDFData {
                    AIInsightsShareSheet(activityItems: [pdfData])
                }
            }
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
                                if state.weeklyReportPDFData != nil {
                                    Button(action: {
                                        showShareSheet = true
                                    }) {
                                        Image(systemName: "square.and.arrow.up")
                                    }
                                }
                            }

                            // Rich markdown rendering
                            RichMarkdownView(content: state.weeklyReport)
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

                                if state.weeklyReportPDFData != nil {
                                    Button(action: {
                                        showShareSheet = true
                                    }) {
                                        HStack {
                                            Image(systemName: "square.and.arrow.up")
                                            Text("Share PDF")
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
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
                if let pdfData = state.weeklyReportPDFData {
                    AIInsightsShareSheet(activityItems: [pdfData])
                }
            }
        }
    }

    // MARK: - Doctor Visit Report View

    struct DoctorVisitReportView: View {
        @ObservedObject var state: StateModel
        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState
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

                            // Data period info
                            Label("Will analyze last \(state.drTimePeriod.displayName)", systemImage: "calendar")
                                .font(.caption)
                                .foregroundColor(.secondary)
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
                                Label(state.drTimePeriod.displayName, systemImage: "calendar")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            // Rich markdown rendering
                            RichMarkdownView(content: state.doctorVisitReport)
                                .padding()
                                .background(Color.chart)
                                .cornerRadius(12)

                            // Share and regenerate buttons
                            HStack {
                                Button(action: {
                                    Task {
                                        await state.generateDoctorVisitReport()
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "arrow.clockwise")
                                        Text("Regenerate")
                                    }
                                }
                                .buttonStyle(.bordered)

                                Spacer()

                                if state.doctorReportPDFData != nil {
                                    Button(action: {
                                        showPDFShare = true
                                    }) {
                                        HStack {
                                            Image(systemName: "square.and.arrow.up")
                                            Text("Share PDF")
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.purple)
                                }
                            }
                        }
                        .padding()
                    }

                    Spacer()
                }
            }
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Doctor Visit Report")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: DoctorReportSettingsView(state: state)) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showPDFShare) {
                if let pdfData = state.doctorReportPDFData {
                    AIInsightsShareSheet(activityItems: [pdfData])
                }
            }
        }
    }

    // MARK: - Quick Analysis Settings View

    struct QuickAnalysisSettingsView: View {
        @ObservedObject var state: StateModel
        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState
        @State private var showResetPromptAlert = false

        var body: some View {
            Form {
                Section(
                    header: Text("Time Period"),
                    footer: Text("Select how much historical data to analyze. Longer periods provide more context but may take longer to process.")
                ) {
                    Picker("Data Period", selection: $state.qaTimePeriod) {
                        ForEach(TimePeriod.allCases) { period in
                            Text(period.displayName).tag(period)
                        }
                    }
                    .onChange(of: state.qaTimePeriod) { _, _ in state.saveQuickAnalysisSettings() }
                }
                .listRowBackground(Color.chart)

                Section(
                    header: Text("Data to Include"),
                    footer: Text("Toggle which sections of your treatment data to include in the analysis sent to Claude.")
                ) {
                    Toggle("Insulin Settings (DIA, Max IOB, Max Bolus)", isOn: $state.qaShowInsulinSettings)
                        .onChange(of: state.qaShowInsulinSettings) { _, _ in state.saveQuickAnalysisSettings() }

                    Toggle("Carb Ratios", isOn: $state.qaShowCarbRatios)
                        .onChange(of: state.qaShowCarbRatios) { _, _ in state.saveQuickAnalysisSettings() }

                    Toggle("Insulin Sensitivity Factors (ISF)", isOn: $state.qaShowISF)
                        .onChange(of: state.qaShowISF) { _, _ in state.saveQuickAnalysisSettings() }

                    Toggle("Basal Rates", isOn: $state.qaShowBasalRates)
                        .onChange(of: state.qaShowBasalRates) { _, _ in state.saveQuickAnalysisSettings() }

                    Toggle("Target Glucose Ranges", isOn: $state.qaShowTargets)
                        .onChange(of: state.qaShowTargets) { _, _ in state.saveQuickAnalysisSettings() }
                }
                .listRowBackground(Color.chart)

                Section(
                    header: Text("Statistics & History"),
                    footer: Text("Include glucose statistics and detailed treatment history.")
                ) {
                    Toggle("Statistics Summary", isOn: $state.qaShowStatistics)
                        .onChange(of: state.qaShowStatistics) { _, _ in state.saveQuickAnalysisSettings() }

                    Toggle("Loop Data (BG, IOB, COB, Temp Basals)", isOn: $state.qaShowLoopData)
                        .onChange(of: state.qaShowLoopData) { _, _ in state.saveQuickAnalysisSettings() }

                    Toggle("Carb Entries", isOn: $state.qaShowCarbEntries)
                        .onChange(of: state.qaShowCarbEntries) { _, _ in state.saveQuickAnalysisSettings() }

                    Toggle("Bolus History", isOn: $state.qaShowBolusHistory)
                        .onChange(of: state.qaShowBolusHistory) { _, _ in state.saveQuickAnalysisSettings() }
                }
                .listRowBackground(Color.chart)

                Section(
                    header: Text("AI Prompt"),
                    footer: Text("Customize the instructions sent to Claude for analyzing your data.")
                ) {
                    TextEditor(text: $state.qaCustomPrompt)
                        .frame(minHeight: 150)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: state.qaCustomPrompt) { _, _ in state.saveQuickAnalysisSettings() }

                    Button(action: {
                        showResetPromptAlert = true
                    }) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset to Default Prompt")
                        }
                        .foregroundColor(.red)
                    }
                }
                .listRowBackground(Color.chart)
            }
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Quick Analysis Settings")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Reset Prompt?", isPresented: $showResetPromptAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    state.resetQuickAnalysisPrompt()
                }
            } message: {
                Text("This will reset the AI prompt to the default. Your custom prompt will be lost.")
            }
        }
    }

    // MARK: - Doctor Report Settings View

    struct DoctorReportSettingsView: View {
        @ObservedObject var state: StateModel
        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState
        @State private var showResetPromptAlert = false

        var body: some View {
            Form {
                Section(
                    header: Text("Time Period"),
                    footer: Text("Select how much historical data to include in the report. More data provides better trend analysis.")
                ) {
                    Picker("Data Period", selection: $state.drTimePeriod) {
                        ForEach(TimePeriod.allCases) { period in
                            Text(period.displayName).tag(period)
                        }
                    }
                    .onChange(of: state.drTimePeriod) { _, _ in state.saveDoctorReportSettings() }
                }
                .listRowBackground(Color.chart)

                Section(
                    header: Text("Data to Include"),
                    footer: Text("Toggle which sections of your treatment data to include in the report sent to Claude.")
                ) {
                    Toggle("Insulin Settings (DIA, Max IOB, Max Bolus)", isOn: $state.drShowInsulinSettings)
                        .onChange(of: state.drShowInsulinSettings) { _, _ in state.saveDoctorReportSettings() }

                    Toggle("Carb Ratios", isOn: $state.drShowCarbRatios)
                        .onChange(of: state.drShowCarbRatios) { _, _ in state.saveDoctorReportSettings() }

                    Toggle("Insulin Sensitivity Factors (ISF)", isOn: $state.drShowISF)
                        .onChange(of: state.drShowISF) { _, _ in state.saveDoctorReportSettings() }

                    Toggle("Basal Rates", isOn: $state.drShowBasalRates)
                        .onChange(of: state.drShowBasalRates) { _, _ in state.saveDoctorReportSettings() }

                    Toggle("Target Glucose Ranges", isOn: $state.drShowTargets)
                        .onChange(of: state.drShowTargets) { _, _ in state.saveDoctorReportSettings() }
                }
                .listRowBackground(Color.chart)

                Section(
                    header: Text("Statistics & History"),
                    footer: Text("Include glucose statistics and detailed treatment history.")
                ) {
                    Toggle("Multi-Timeframe Statistics", isOn: $state.drShowStatistics)
                        .onChange(of: state.drShowStatistics) { _, _ in state.saveDoctorReportSettings() }

                    Toggle("Loop Data (BG, IOB, COB, Temp Basals)", isOn: $state.drShowLoopData)
                        .onChange(of: state.drShowLoopData) { _, _ in state.saveDoctorReportSettings() }

                    Toggle("Carb Entries", isOn: $state.drShowCarbEntries)
                        .onChange(of: state.drShowCarbEntries) { _, _ in state.saveDoctorReportSettings() }

                    Toggle("Bolus History", isOn: $state.drShowBolusHistory)
                        .onChange(of: state.drShowBolusHistory) { _, _ in state.saveDoctorReportSettings() }
                }
                .listRowBackground(Color.chart)

                Section(
                    header: Text("AI Prompt"),
                    footer: Text("Customize the instructions sent to Claude for analyzing your data. This tells Claude what kind of report to generate.")
                ) {
                    TextEditor(text: $state.drCustomPrompt)
                        .frame(minHeight: 300)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: state.drCustomPrompt) { _, _ in state.saveDoctorReportSettings() }

                    Button(action: {
                        showResetPromptAlert = true
                    }) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset to Default Prompt")
                        }
                        .foregroundColor(.red)
                    }
                }
                .listRowBackground(Color.chart)
            }
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Report Settings")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Reset Prompt?", isPresented: $showResetPromptAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    state.resetDoctorReportPrompt()
                }
            } message: {
                Text("This will reset the AI prompt to the default. Your custom prompt will be lost.")
            }
        }
    }

    // MARK: - Why High/Low Settings View

    struct WhyHighLowSettingsView: View {
        @ObservedObject var state: StateModel
        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState
        @State private var showResetPromptAlert = false

        // Slider ranges based on units
        private var highThresholdRange: ClosedRange<Double> {
            state.units == .mmolL ? 6.7...16.0 : 120.0...300.0
        }

        private var lowThresholdRange: ClosedRange<Double> {
            state.units == .mmolL ? 2.5...6.1 : 50.0...110.0
        }

        private var sliderStep: Double {
            state.units == .mmolL ? 0.5 : 5.0
        }

        private func formatThreshold(_ value: Decimal) -> String {
            let number = NSDecimalNumber(decimal: value).doubleValue
            if state.units == .mmolL {
                return String(format: "%.1f", number)
            } else {
                return String(format: "%.0f", number)
            }
        }

        var body: some View {
            Form {
                Section(
                    header: Text("Glucose Thresholds"),
                    footer: Text("Set the glucose levels that trigger the \"Why High\" or \"Why Low\" analysis banner on the home screen.")
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("High Threshold")
                            Spacer()
                            Text("\(formatThreshold(state.whlHighThreshold)) \(state.units.rawValue)")
                                .fontWeight(.medium)
                                .foregroundColor(.orange)
                        }
                        Slider(
                            value: Binding(
                                get: { NSDecimalNumber(decimal: state.whlHighThreshold).doubleValue },
                                set: { state.whlHighThreshold = Decimal($0) }
                            ),
                            in: highThresholdRange,
                            step: sliderStep
                        )
                        .tint(.orange)
                        .onChange(of: state.whlHighThreshold) { _, _ in
                            state.saveWhyHighLowSettings()
                        }
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Low Threshold")
                            Spacer()
                            Text("\(formatThreshold(state.whlLowThreshold)) \(state.units.rawValue)")
                                .fontWeight(.medium)
                                .foregroundColor(.red)
                        }
                        Slider(
                            value: Binding(
                                get: { NSDecimalNumber(decimal: state.whlLowThreshold).doubleValue },
                                set: { state.whlLowThreshold = Decimal($0) }
                            ),
                            in: lowThresholdRange,
                            step: sliderStep
                        )
                        .tint(.red)
                        .onChange(of: state.whlLowThreshold) { _, _ in
                            state.saveWhyHighLowSettings()
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.chart)

                Section(
                    header: Text("Analysis Period"),
                    footer: Text("How far back to look when analyzing why your glucose is out of range. Shorter periods focus on recent events.")
                ) {
                    Picker("Look Back", selection: $state.whlAnalysisHours) {
                        ForEach(AnalysisHours.allCases) { hours in
                            Text(hours.displayName).tag(hours)
                        }
                    }
                    .onChange(of: state.whlAnalysisHours) { _, _ in state.saveWhyHighLowSettings() }
                }
                .listRowBackground(Color.chart)

                Section(
                    header: Text("AI Prompt"),
                    footer: Text("Customize the instructions sent to Claude when analyzing why your glucose is out of range.")
                ) {
                    TextEditor(text: $state.whlCustomPrompt)
                        .frame(minHeight: 150)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: state.whlCustomPrompt) { _, _ in state.saveWhyHighLowSettings() }

                    Button(action: {
                        showResetPromptAlert = true
                    }) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset to Default Prompt")
                        }
                        .foregroundColor(.red)
                    }
                }
                .listRowBackground(Color.chart)
            }
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Why High/Low Settings")
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear {
                // Ensure settings are saved when leaving the view
                state.saveWhyHighLowSettings()
            }
            .alert("Reset Prompt?", isPresented: $showResetPromptAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    state.resetWhyHighLowPrompt()
                }
            } message: {
                Text("This will reset the AI prompt to the default. Your custom prompt will be lost.")
            }
        }
    }

    // MARK: - Photo Carb Settings View

    struct PhotoCarbSettingsView: View {
        @ObservedObject var state: StateModel
        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState
        @State private var showResetPromptAlert = false

        var body: some View {
            Form {
                Section(
                    header: Text("Portion Size"),
                    footer: Text("Default assumption for portion sizes when not specified in the photo description.")
                ) {
                    Picker("Default Portion", selection: $state.photoDefaultPortion) {
                        ForEach(PortionSize.allCases) { size in
                            Text(size.displayName).tag(size)
                        }
                    }
                    .onChange(of: state.photoDefaultPortion) { _, _ in state.savePhotoCarbSettings() }
                }
                .listRowBackground(Color.chart)

                Section(
                    header: Text("AI Prompt"),
                    footer: Text("Customize the instructions sent to Claude when estimating carbs from food photos.")
                ) {
                    TextEditor(text: $state.photoCustomPrompt)
                        .frame(minHeight: 200)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: state.photoCustomPrompt) { _, _ in state.savePhotoCarbSettings() }

                    Button(action: {
                        showResetPromptAlert = true
                    }) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset to Default Prompt")
                        }
                        .foregroundColor(.red)
                    }
                }
                .listRowBackground(Color.chart)
            }
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Photo Carb Settings")
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear {
                // Ensure settings are saved when leaving the view
                state.savePhotoCarbSettings()
            }
            .alert("Reset Prompt?", isPresented: $showResetPromptAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    state.resetPhotoCarbPrompt()
                }
            } message: {
                Text("This will reset the AI prompt to the default. Your custom prompt will be lost.")
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

    // MARK: - Why High/Low Analysis View

    struct WhyHighLowAnalysisView: View {
        @ObservedObject var state: StateModel
        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState
        @Environment(\.dismiss) var dismiss
        @State private var showShareSheet = false

        let currentBG: Decimal
        let bgTrend: String
        let currentIOB: Decimal
        let currentCOB: Int
        let isHigh: Bool

        var body: some View {
            NavigationView {
                ScrollView {
                    VStack(spacing: 20) {
                        // Current Status Card
                        currentStatusCard

                        // Analysis Result or Loading
                        if state.isAnalyzingWhyHighLow {
                            loadingView
                        } else if let error = state.whyHighLowError {
                            errorView(error)
                        } else if !state.whyHighLowResult.isEmpty {
                            resultView
                        } else {
                            analyzeButton
                        }
                    }
                    .padding()
                }
                .background(appState.trioBackgroundColor(for: colorScheme))
                .navigationTitle(isHigh ? "Why Am I High?" : "Why Am I Low?")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Close") {
                            dismiss()
                        }
                    }

                    if !state.whyHighLowResult.isEmpty {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(action: { showShareSheet = true }) {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                    }
                }
                .sheet(isPresented: $showShareSheet) {
                    if let pdfData = state.whyHighLowPDFData {
                        ShareSheet(activityItems: [pdfData])
                    }
                }
            }
            .onAppear {
                // Auto-analyze when view appears
                Task {
                    await state.analyzeWhyHighLow(
                        currentBG: currentBG,
                        bgTrend: bgTrend,
                        currentIOB: currentIOB,
                        currentCOB: currentCOB,
                        isHigh: isHigh
                    )
                }
            }
            .onDisappear {
                state.clearWhyHighLowResult()
            }
        }

        private var currentStatusCard: some View {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: isHigh ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .font(.title)
                        .foregroundColor(isHigh ? .orange : .red)

                    VStack(alignment: .leading) {
                        Text("Current BG: \(NSDecimalNumber(decimal: currentBG).intValue) \(state.units.rawValue)")
                            .font(.headline)
                        Text("Trend: \(bgTrend)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                HStack(spacing: 20) {
                    VStack {
                        Text("IOB")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(String(format: "%.2f", NSDecimalNumber(decimal: currentIOB).doubleValue)) U")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }

                    Divider()
                        .frame(height: 30)

                    VStack {
                        Text("COB")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(currentCOB) g")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }

                    Divider()
                        .frame(height: 30)

                    VStack {
                        Text("Analysis Period")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(state.whlAnalysisHours.displayName)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
            }
            .padding()
            .background(Color.chart)
            .cornerRadius(12)
        }

        private var loadingView: some View {
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Analyzing your data...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(40)
            .background(Color.chart)
            .cornerRadius(12)
        }

        private func errorView(_ error: String) -> some View {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title)
                    .foregroundColor(.orange)
                Text("Analysis Error")
                    .font(.headline)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button("Try Again") {
                    Task {
                        await state.analyzeWhyHighLow(
                            currentBG: currentBG,
                            bgTrend: bgTrend,
                            currentIOB: currentIOB,
                            currentCOB: currentCOB,
                            isHigh: isHigh
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.chart)
            .cornerRadius(12)
        }

        private var resultView: some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "brain.head.profile")
                        .foregroundColor(.purple)
                    Text("AI Analysis")
                        .font(.headline)
                }

                RichMarkdownView(content: state.whyHighLowResult)

                // Disclaimer
                Text("This analysis is for informational purposes only. Always consult your healthcare provider before making treatment changes.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
            .padding()
            .background(Color.chart)
            .cornerRadius(12)
        }

        private var analyzeButton: some View {
            Button(action: {
                Task {
                    await state.analyzeWhyHighLow(
                        currentBG: currentBG,
                        bgTrend: bgTrend,
                        currentIOB: currentIOB,
                        currentCOB: currentCOB,
                        isHigh: isHigh
                    )
                }
            }) {
                HStack {
                    Image(systemName: "brain.head.profile")
                    Text("Analyze")
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!state.isAPIKeyConfigured)
        }
    }

    // MARK: - Photo Carb Estimate View

    struct PhotoCarbEstimateView: View {
        @ObservedObject var state: StateModel
        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState
        @Environment(\.dismiss) var dismiss

        @State private var showImagePicker = false
        @State private var imagePickerSourceType: UIImagePickerController.SourceType = .photoLibrary
        @State private var showCameraUnavailableAlert = false

        /// Check if camera is available on this device
        private var isCameraAvailable: Bool {
            UIImagePickerController.isSourceTypeAvailable(.camera)
        }

        /// Optional callback when user accepts the carb estimate (for integration with bolus calculator)
        var onAcceptCarbs: ((Decimal) -> Void)?

        var body: some View {
            ScrollView {
                VStack(spacing: 20) {
                    // Photo Selection Section
                    photoSelectionSection

                    // Description Input
                    descriptionSection

                    // Estimate Button
                    if state.selectedFoodImage != nil {
                        estimateButton
                    }

                    // Results Section
                    if state.isEstimatingCarbs {
                        loadingView
                    } else if let error = state.carbEstimateError {
                        errorView(error)
                    } else if let result = state.carbEstimateResult {
                        resultView(result)
                    }
                }
                .padding()
            }
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Estimate Carbs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if state.selectedFoodImage != nil || state.carbEstimateResult != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Clear") {
                            state.clearCarbEstimate()
                        }
                    }
                }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(
                    image: $state.selectedFoodImage,
                    sourceType: imagePickerSourceType
                )
            }
            .alert("Camera Unavailable", isPresented: $showCameraUnavailableAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Camera is not available on this device. Please use the Photos option to select an image.")
            }
            .onDisappear {
                // Only clear if not accepting carbs
                if onAcceptCarbs == nil {
                    state.clearCarbEstimate()
                }
            }
        }

        private var photoSelectionSection: some View {
            VStack(spacing: 16) {
                if let image = state.selectedFoodImage {
                    // Show selected image
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 250)
                        .cornerRadius(12)
                        .shadow(radius: 4)

                    // Change photo button
                    HStack {
                        Button(action: {
                            if isCameraAvailable {
                                imagePickerSourceType = .camera
                                showImagePicker = true
                            } else {
                                showCameraUnavailableAlert = true
                            }
                        }) {
                            Label("Retake", systemImage: "camera")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!isCameraAvailable)

                        Button(action: {
                            imagePickerSourceType = .photoLibrary
                            showImagePicker = true
                        }) {
                            Label("Choose Another", systemImage: "photo")
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    // Photo selection buttons
                    VStack(spacing: 12) {
                        Image(systemName: "fork.knife.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.mint.opacity(0.6))

                        Text("Take or select a photo of your meal")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        HStack(spacing: 20) {
                            Button(action: {
                                if isCameraAvailable {
                                    imagePickerSourceType = .camera
                                    showImagePicker = true
                                } else {
                                    showCameraUnavailableAlert = true
                                }
                            }) {
                                VStack {
                                    Image(systemName: "camera.fill")
                                        .font(.title)
                                    Text("Camera")
                                        .font(.caption)
                                }
                                .frame(width: 100, height: 80)
                            }
                            .buttonStyle(.bordered)
                            .tint(isCameraAvailable ? .mint : .gray)
                            .disabled(!isCameraAvailable)

                            Button(action: {
                                imagePickerSourceType = .photoLibrary
                                showImagePicker = true
                            }) {
                                VStack {
                                    Image(systemName: "photo.fill")
                                        .font(.title)
                                    Text("Photos")
                                        .font(.caption)
                                }
                                .frame(width: 100, height: 80)
                            }
                            .buttonStyle(.bordered)
                            .tint(.blue)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(30)
                    .background(Color.chart)
                    .cornerRadius(12)
                }
            }
        }

        private var descriptionSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Description (optional)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextField("e.g., small portion, dressing on the side", text: $state.foodDescription)
                    .textFieldStyle(.roundedBorder)
            }
            .padding()
            .background(Color.chart)
            .cornerRadius(12)
        }

        private var estimateButton: some View {
            Button(action: {
                Task {
                    await state.estimateCarbsFromPhoto()
                }
            }) {
                HStack {
                    Image(systemName: "sparkles")
                    Text("Estimate Carbs")
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .buttonStyle(.borderedProminent)
            .tint(.mint)
            .disabled(!AIInsightsConfig.Config.isAPIKeyConfigured || state.isEstimatingCarbs)
        }

        private var loadingView: some View {
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Analyzing your meal...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(40)
            .background(Color.chart)
            .cornerRadius(12)
        }

        private func errorView(_ error: String) -> some View {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title)
                    .foregroundColor(.orange)
                Text("Estimation Error")
                    .font(.headline)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button("Try Again") {
                    Task {
                        await state.estimateCarbsFromPhoto()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.chart)
            .cornerRadius(12)
        }

        private func resultView(_ result: CarbEstimateResult) -> some View {
            VStack(alignment: .leading, spacing: 16) {
                // Header with total
                HStack {
                    VStack(alignment: .leading) {
                        Text("Estimated Carbs")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("\(NSDecimalNumber(decimal: result.totalCarbs).intValue)g")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.mint)
                    }

                    Spacer()

                    // Confidence badge
                    VStack {
                        Text("Confidence")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(result.confidence.rawValue)
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(confidenceColor(result.confidence).opacity(0.2))
                            .foregroundColor(confidenceColor(result.confidence))
                            .cornerRadius(12)
                    }
                }

                Divider()

                // Itemized breakdown
                if !result.items.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Breakdown")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        ForEach(result.items) { item in
                            HStack {
                                Text("🍽️")
                                VStack(alignment: .leading) {
                                    Text(item.name)
                                        .font(.subheadline)
                                    if !item.portion.isEmpty {
                                        Text(item.portion)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Text("~\(NSDecimalNumber(decimal: item.carbs).intValue)g")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                // Notes
                if let notes = result.notes {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Text(notes)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                // Action buttons
                if let onAccept = onAcceptCarbs {
                    // From bolus calculator - button to use carbs
                    Button(action: {
                        onAccept(result.totalCarbs)
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Use \(NSDecimalNumber(decimal: result.totalCarbs).intValue)g in Calculator")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                } else {
                    // Standalone mode - show carbs prominently with copy option
                    VStack(spacing: 12) {
                        Text("Estimated Carbs")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(NSDecimalNumber(decimal: result.totalCarbs).intValue)g")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.mint)

                        Button(action: {
                            UIPasteboard.general.string = "\(NSDecimalNumber(decimal: result.totalCarbs).intValue)"
                        }) {
                            HStack {
                                Image(systemName: "doc.on.doc")
                                Text("Copy to Clipboard")
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.mint)
                    }
                    .padding(.vertical, 8)
                }

                // Show raw response option
                DisclosureGroup("View Full Analysis") {
                    RichMarkdownView(content: result.rawResponse)
                        .padding(.top, 8)
                }
                .font(.caption)
            }
            .padding()
            .background(Color.chart)
            .cornerRadius(12)
        }

        private func confidenceColor(_ confidence: CarbEstimateResult.ConfidenceLevel) -> Color {
            switch confidence {
            case .low: return .red
            case .medium: return .orange
            case .high: return .green
            }
        }
    }

    // MARK: - Image Picker

    struct ImagePicker: UIViewControllerRepresentable {
        @Binding var image: UIImage?
        let sourceType: UIImagePickerController.SourceType
        @Environment(\.dismiss) var dismiss

        func makeUIViewController(context: Context) -> UIImagePickerController {
            let picker = UIImagePickerController()
            picker.sourceType = sourceType
            picker.delegate = context.coordinator
            return picker
        }

        func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }

        class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
            let parent: ImagePicker

            init(_ parent: ImagePicker) {
                self.parent = parent
            }

            func imagePickerController(
                _ picker: UIImagePickerController,
                didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
            ) {
                if let image = info[.originalImage] as? UIImage {
                    parent.image = image
                }
                parent.dismiss()
            }

            func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
                parent.dismiss()
            }
        }
    }

    // MARK: - Saved Reports List View

    struct SavedReportsListView: View {
        @ObservedObject var state: StateModel
        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            List {
                ForEach(SavedReportsManager.ReportType.allCases, id: \.rawValue) { type in
                    let reportsOfType = state.savedReports.filter { $0.type == type.rawValue }
                    if !reportsOfType.isEmpty {
                        Section(header: Text(type.displayName)) {
                            ForEach(reportsOfType) { report in
                                NavigationLink(destination: SavedReportDetailView(report: report)) {
                                    SavedReportRow(report: report)
                                }
                            }
                            .onDelete { indexSet in
                                for index in indexSet {
                                    state.deleteSavedReport(reportsOfType[index])
                                }
                            }
                        }
                        .listRowBackground(Color.chart)
                    }
                }

                if state.savedReports.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("No Saved Reports")
                                .font(.headline)
                            Text("Reports are automatically saved when generated.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                    .listRowBackground(Color.chart)
                }
            }
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Saved Reports")
            .onAppear {
                state.loadSavedReports()
            }
        }
    }

    struct SavedReportRow: View {
        let report: SavedReportsManager.SavedReport

        var body: some View {
            HStack(spacing: 12) {
                // Report type icon
                Image(systemName: report.reportType?.icon ?? "doc")
                    .foregroundColor(iconColor)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(report.reportType?.displayName ?? "Report")
                        .font(.headline)

                    HStack {
                        Text(report.formattedDate)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("•")
                            .foregroundColor(.secondary)

                        Text(report.timePeriod)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 4)
        }

        private var iconColor: Color {
            switch report.reportType {
            case .quickAnalysis: return .yellow
            case .weeklyReport: return .green
            case .doctorReport: return .purple
            case .claudeOTune: return .blue
            case .none: return .gray
            }
        }
    }

    // MARK: - PDF Viewer for Saved Reports

    struct PDFViewer: UIViewRepresentable {
        let data: Data

        func makeUIView(context: Context) -> PDFView {
            let pdfView = PDFView()
            pdfView.autoScales = true
            pdfView.displayMode = .singlePageContinuous
            pdfView.displayDirection = .vertical
            if let document = PDFDocument(data: data) {
                pdfView.document = document
            }
            return pdfView
        }

        func updateUIView(_ uiView: PDFView, context: Context) {
            if let document = PDFDocument(data: data) {
                uiView.document = document
            }
        }
    }

    // MARK: - Saved Report Detail View

    struct SavedReportDetailView: View {
        let report: SavedReportsManager.SavedReport
        @State private var pdfData: Data?
        @State private var showShareSheet = false
        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            Group {
                if let data = pdfData {
                    PDFViewer(data: data)
                        .edgesIgnoringSafeArea(.bottom)
                } else {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading report...")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(report.reportType?.displayName ?? "Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showShareSheet = true
                    }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(pdfData == nil)
                }
            }
            .onAppear {
                pdfData = SavedReportsManager.shared.getPDFData(for: report)
            }
            .sheet(isPresented: $showShareSheet) {
                if let data = pdfData {
                    AIInsightsShareSheet(activityItems: [data])
                }
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

    // MARK: - Claude-o-Tune View

    struct ClaudeOTuneView: View {
        @ObservedObject var state: StateModel
        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState
        @State private var showShareSheet = false

        var body: some View {
            ScrollView {
                VStack(spacing: 20) {
                    if state.claudeOTuneResult == nil && state.claudeOTuneRawResponse.isEmpty && !state.isRunningClaudeOTune {
                        // Initial state
                        initialStateView
                    }

                    if state.isRunningClaudeOTune {
                        loadingView
                    }

                    if let error = state.claudeOTuneError, state.claudeOTuneResult == nil && state.claudeOTuneRawResponse.isEmpty {
                        errorView(error)
                    }

                    if let result = state.claudeOTuneResult {
                        resultView(result)
                    } else if !state.claudeOTuneRawResponse.isEmpty {
                        // Fallback to raw response if parsing failed
                        rawResponseView
                    }

                    Spacer()
                }
                .padding()
            }
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Claude-o-Tune")
            .navigationBarTitleDisplayMode(.automatic)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: ClaudeOTuneSettingsView(state: state)) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let pdfData = state.claudeOTunePDFData {
                    AIInsightsShareSheet(activityItems: [pdfData])
                }
            }
        }

        private var initialStateView: some View {
            VStack(spacing: 16) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 50))
                    .foregroundColor(.blue)

                Text("Claude-o-Tune")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("AI-powered profile optimization")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Text(
                    "Analyze your glucose data and get personalized recommendations for basal rates, ISF, and carb ratios. All recommendations are advisory only."
                )
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

                // Data period info
                Label("Will analyze last \(state.cotTimePeriod.displayName)", systemImage: "calendar")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Advisory warning
                advisoryWarningCard

                Button(action: {
                    Task {
                        await state.runClaudeOTuneAnalysis()
                    }
                }) {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Analyze & Optimize")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(state.isAPIKeyConfigured ? Color.blue : Color.gray)
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

        private var advisoryWarningCard: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Advisory Mode Only")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                Text(
                    "Claude-o-Tune provides recommendations only. It does NOT automatically change your profile settings. Always review recommendations with your healthcare provider before making any changes."
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal)
        }

        private var loadingView: some View {
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Analyzing your data...")
                    .foregroundColor(.secondary)
                Text("This may take a minute for \(state.cotTimePeriod.displayName) of data")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 60)
        }

        private func errorView(_ error: String) -> some View {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.red)
                Text(error)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)

                Button("Try Again") {
                    Task {
                        await state.runClaudeOTuneAnalysis()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }

        private func resultView(_ result: ClaudeOTuneRecommendation) -> some View {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Analysis Complete")
                        .font(.headline)
                    Spacer()
                    confidenceBadge(result.confidence)
                }

                // Summary card
                summaryCard(result)

                // Metrics card
                metricsCard(result)

                // Patterns detected
                if !result.patternsDetected.isEmpty {
                    patternsCard(result.patternsDetected)
                }

                // Recommendations
                if !result.adjustments.isEmpty {
                    recommendationsCard(result.adjustments)
                }

                // Concerns
                if !result.concerns.isEmpty {
                    concernsCard(result.concerns)
                }

                // Explanation
                explanationCard(result.explanation)

                // Action buttons
                actionButtons
            }
        }

        private var rawResponseView: some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "doc.text.fill")
                        .foregroundColor(.blue)
                    Text("Analysis Result")
                        .font(.headline)
                }

                if let error = state.claudeOTuneError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.bottom, 8)
                }

                RichMarkdownView(content: state.claudeOTuneRawResponse)
                    .padding()
                    .background(Color.chart)
                    .cornerRadius(12)

                actionButtons
            }
        }

        private func confidenceBadge(_ confidence: ClaudeOTuneRecommendation.ConfidenceLevel) -> some View {
            Text(confidence.displayName)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(confidenceColor(confidence).opacity(0.2))
                .foregroundColor(confidenceColor(confidence))
                .cornerRadius(12)
        }

        private func confidenceColor(_ confidence: ClaudeOTuneRecommendation.ConfidenceLevel) -> Color {
            switch confidence {
            case .low: return .red
            case .medium: return .orange
            case .high: return .green
            }
        }

        private func summaryCard(_ result: ClaudeOTuneRecommendation) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Summary")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Text(result.analysisSummary)
                    .font(.body)

                HStack {
                    Label("Data Quality: \(result.dataQuality.score)/100", systemImage: "chart.bar.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Label("\(result.totalRecommendedChanges) changes", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(Color.chart)
            .cornerRadius(12)
        }

        private func metricsCard(_ result: ClaudeOTuneRecommendation) -> some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("Current Metrics")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                HStack(spacing: 16) {
                    metricItem(
                        "TIR",
                        value: String(format: "%.0f%%", result.currentMetrics.timeInRange),
                        color: result.currentMetrics.timeInRange >= 70 ? .green : .orange
                    )
                    metricItem(
                        "TBR",
                        value: String(format: "%.0f%%", result.currentMetrics.timeBelowRange),
                        color: result.currentMetrics.timeBelowRange < 4 ? .green : .red
                    )
                    metricItem(
                        "TAR",
                        value: String(format: "%.0f%%", result.currentMetrics.timeAboveRange),
                        color: result.currentMetrics.timeAboveRange < 25 ? .green : .orange
                    )
                    metricItem(
                        "CV",
                        value: String(format: "%.0f%%", result.currentMetrics.glucoseVariability),
                        color: result.currentMetrics.glucoseVariability < 36 ? .green : .orange
                    )
                }

                HStack {
                    Label(
                        "Avg: \(result.currentMetrics.averageGlucose) \(state.units.rawValue)",
                        systemImage: "waveform.path.ecg"
                    )
                    .font(.caption)
                    Spacer()
                    Label("GMI: \(String(format: "%.1f", result.currentMetrics.gmi))%", systemImage: "percent")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.chart)
            .cornerRadius(12)
        }

        private func metricItem(_ label: String, value: String, color: Color) -> some View {
            VStack(spacing: 4) {
                Text(value)
                    .font(.headline)
                    .foregroundColor(color)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }

        private func patternsCard(_ patterns: [ClaudeOTuneRecommendation.PatternDetected]) -> some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("Patterns Detected")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                ForEach(patterns) { pattern in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: patternIcon(pattern.patternType))
                            .foregroundColor(.blue)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(pattern.description)
                                .font(.subheadline)
                            HStack {
                                Text(pattern.frequency)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("•")
                                    .foregroundColor(.secondary)
                                Text(pattern.impact)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        confidenceBadge(pattern.confidence)
                    }
                    .padding(.vertical, 4)

                    if pattern.id != patterns.last?.id {
                        Divider()
                    }
                }
            }
            .padding()
            .background(Color.chart)
            .cornerRadius(12)
        }

        private func patternIcon(_ patternType: String) -> String {
            switch patternType.lowercased() {
            case "dawn_phenomenon": return "sunrise.fill"
            case "post_exercise": return "figure.run"
            case "post_meal": return "fork.knife"
            case "overnight": return "moon.fill"
            case "afternoon_resistance": return "sun.max.fill"
            default: return "waveform.path.ecg"
            }
        }

        private func recommendationsCard(_ adjustments: [ClaudeOTuneRecommendation.ProfileAdjustment]) -> some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Recommended Changes")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Advisory Only")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(8)
                }

                ForEach(adjustments.sorted { $0.priority < $1.priority }) { adjustment in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            priorityBadge(adjustment.priority)
                            Text(adjustment.parameter.uppercased())
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text(adjustment.timePeriod)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            confidenceBadge(adjustment.confidence)
                        }

                        HStack {
                            Text("\(adjustment.oldValue)")
                                .foregroundColor(.secondary)
                            Image(systemName: "arrow.right")
                                .foregroundColor(.blue)
                            Text("\(adjustment.newValue)")
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                            Text("(\(adjustment.percentChange > 0 ? "+" : "")\(String(format: "%.1f", adjustment.percentChange))%)")
                                .font(.caption)
                                .foregroundColor(adjustment.percentChange > 0 ? .orange : .green)
                        }
                        .font(.subheadline)

                        Text(adjustment.rationale)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.chart.opacity(0.5))
                    .cornerRadius(8)
                }
            }
            .padding()
            .background(Color.chart)
            .cornerRadius(12)
        }

        private func priorityBadge(_ priority: Int) -> some View {
            Text("P\(priority)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(priorityColor(priority))
                .cornerRadius(4)
        }

        private func priorityColor(_ priority: Int) -> Color {
            switch priority {
            case 1: return .red
            case 2: return .orange
            case 3: return .yellow
            default: return .gray
            }
        }

        private func concernsCard(_ concerns: [ClaudeOTuneRecommendation.SafetyConcern]) -> some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text("Safety Concerns")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                ForEach(concerns) { concern in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            severityBadge(concern.severity)
                            Text(concern.description)
                                .font(.subheadline)
                        }
                        Text(concern.recommendation)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(severityBackgroundColor(concern.severity))
                    .cornerRadius(8)
                }
            }
            .padding()
            .background(Color.chart)
            .cornerRadius(12)
        }

        private func severityBadge(_ severity: ClaudeOTuneRecommendation.SafetyConcern.Severity) -> some View {
            Text(severity.displayName)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(severityColor(severity))
                .cornerRadius(4)
        }

        private func severityColor(_ severity: ClaudeOTuneRecommendation.SafetyConcern.Severity) -> Color {
            switch severity {
            case .high: return .red
            case .medium: return .orange
            case .low: return .yellow
            }
        }

        private func severityBackgroundColor(_ severity: ClaudeOTuneRecommendation.SafetyConcern.Severity) -> Color {
            switch severity {
            case .high: return .red.opacity(0.1)
            case .medium: return .orange.opacity(0.1)
            case .low: return .yellow.opacity(0.1)
            }
        }

        private func explanationCard(_ explanation: String) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "brain.head.profile")
                        .foregroundColor(.purple)
                    Text("AI Analysis")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                Text(explanation)
                    .font(.body)
            }
            .padding()
            .background(Color.chart)
            .cornerRadius(12)
        }

        private var actionButtons: some View {
            VStack(spacing: 12) {
                HStack {
                    Button(action: {
                        Task {
                            await state.runClaudeOTuneAnalysis()
                        }
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Run Again")
                        }
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    if state.claudeOTunePDFData != nil {
                        Button(action: {
                            showShareSheet = true
                        }) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share PDF")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                // Disclaimer
                Text(
                    "These recommendations are for informational purposes only. Always consult your healthcare provider before making any changes to your insulin therapy."
                )
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
            }
            .padding()
        }
    }

    // MARK: - Claude-o-Tune Settings View

    struct ClaudeOTuneSettingsView: View {
        @ObservedObject var state: StateModel
        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState
        @State private var showResetPromptAlert = false

        var body: some View {
            Form {
                Section(
                    header: Text("Analysis Period"),
                    footer: Text(
                        "Longer periods provide more data for pattern detection but take longer to analyze. 30 days is recommended."
                    )
                ) {
                    Picker("Data Period", selection: $state.cotTimePeriod) {
                        ForEach(TimePeriod.allCases) { period in
                            Text(period.displayName).tag(period)
                        }
                    }
                    .onChange(of: state.cotTimePeriod) { _, _ in state.saveClaudeOTuneSettings() }
                }
                .listRowBackground(Color.chart)

                Section(
                    header: Text("Recommendations to Include"),
                    footer: Text("Choose which profile settings Claude-o-Tune should analyze and recommend changes for.")
                ) {
                    Toggle("Pattern Analysis", isOn: $state.cotIncludePatternAnalysis)
                        .onChange(of: state.cotIncludePatternAnalysis) { _, _ in state.saveClaudeOTuneSettings() }

                    Toggle("Basal Rate Recommendations", isOn: $state.cotIncludeBasalRecommendations)
                        .onChange(of: state.cotIncludeBasalRecommendations) { _, _ in state.saveClaudeOTuneSettings() }

                    Toggle("ISF Recommendations", isOn: $state.cotIncludeISFRecommendations)
                        .onChange(of: state.cotIncludeISFRecommendations) { _, _ in state.saveClaudeOTuneSettings() }

                    Toggle("Carb Ratio Recommendations", isOn: $state.cotIncludeCRRecommendations)
                        .onChange(of: state.cotIncludeCRRecommendations) { _, _ in state.saveClaudeOTuneSettings() }
                }
                .listRowBackground(Color.chart)

                Section(
                    header: Text("Safety Limits"),
                    footer: Text(
                        "Maximum percentage change allowed per recommendation. Lower values are more conservative. Your algorithm's autosens limits are also applied."
                    )
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Max Adjustment")
                            Spacer()
                            Text("\(Int(state.cotMaxAdjustmentPercent))%")
                                .fontWeight(.medium)
                                .foregroundColor(.blue)
                        }
                        Slider(value: $state.cotMaxAdjustmentPercent, in: 5 ... 30, step: 5)
                            .tint(.blue)
                            .onChange(of: state.cotMaxAdjustmentPercent) { _, _ in
                                state.saveClaudeOTuneSettings()
                            }
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.chart)

                Section(
                    header: Text("AI Prompt"),
                    footer: Text("Customize the instructions sent to Claude for analyzing your data.")
                ) {
                    TextEditor(text: $state.cotCustomPrompt)
                        .frame(minHeight: 200)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: state.cotCustomPrompt) { _, _ in state.saveClaudeOTuneSettings() }

                    Button(action: {
                        showResetPromptAlert = true
                    }) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset to Default Prompt")
                        }
                        .foregroundColor(.red)
                    }
                }
                .listRowBackground(Color.chart)
            }
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Claude-o-Tune Settings")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Reset Prompt?", isPresented: $showResetPromptAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    state.resetClaudeOTunePrompt()
                }
            } message: {
                Text("This will reset the AI prompt to the default. Your custom prompt will be lost.")
            }
        }
    }
}
