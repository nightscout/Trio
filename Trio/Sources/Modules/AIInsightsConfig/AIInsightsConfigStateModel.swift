import Combine
import CoreData
import PDFKit
import SwiftUI

extension AIInsightsConfig {
    // MARK: - Time Period Enum

    enum TimePeriod: String, CaseIterable, Identifiable {
        case oneDay = "1d"
        case threeDays = "3d"
        case sevenDays = "7d"
        case fourteenDays = "14d"
        case thirtyDays = "30d"
        case ninetyDays = "90d"

        var id: String { rawValue }

        var days: Int {
            switch self {
            case .oneDay: return 1
            case .threeDays: return 3
            case .sevenDays: return 7
            case .fourteenDays: return 14
            case .thirtyDays: return 30
            case .ninetyDays: return 90
            }
        }

        var displayName: String {
            switch self {
            case .oneDay: return "1 Day"
            case .threeDays: return "3 Days"
            case .sevenDays: return "7 Days"
            case .fourteenDays: return "14 Days"
            case .thirtyDays: return "30 Days"
            case .ninetyDays: return "3 Months"
            }
        }
    }

    enum Config {
        static let apiKeyKey = "AIInsightsConfig.claudeAPIKey"
        // Doctor Report Settings Keys
        static let drTimePeriodKey = "AIInsightsConfig.dr.timePeriod"
        static let drShowCarbRatiosKey = "AIInsightsConfig.dr.showCarbRatios"
        static let drShowISFKey = "AIInsightsConfig.dr.showISF"
        static let drShowBasalRatesKey = "AIInsightsConfig.dr.showBasalRates"
        static let drShowTargetsKey = "AIInsightsConfig.dr.showTargets"
        static let drShowInsulinSettingsKey = "AIInsightsConfig.dr.showInsulinSettings"
        static let drShowStatisticsKey = "AIInsightsConfig.dr.showStatistics"
        static let drShowLoopDataKey = "AIInsightsConfig.dr.showLoopData"
        static let drShowCarbEntriesKey = "AIInsightsConfig.dr.showCarbEntries"
        static let drShowBolusHistoryKey = "AIInsightsConfig.dr.showBolusHistory"
        static let drCustomPromptKey = "AIInsightsConfig.dr.customPrompt"
        // Quick Analysis Settings Keys
        static let qaTimePeriodKey = "AIInsightsConfig.qa.timePeriod"
        static let qaShowCarbRatiosKey = "AIInsightsConfig.qa.showCarbRatios"
        static let qaShowISFKey = "AIInsightsConfig.qa.showISF"
        static let qaShowBasalRatesKey = "AIInsightsConfig.qa.showBasalRates"
        static let qaShowTargetsKey = "AIInsightsConfig.qa.showTargets"
        static let qaShowInsulinSettingsKey = "AIInsightsConfig.qa.showInsulinSettings"
        static let qaShowStatisticsKey = "AIInsightsConfig.qa.showStatistics"
        static let qaShowLoopDataKey = "AIInsightsConfig.qa.showLoopData"
        static let qaShowCarbEntriesKey = "AIInsightsConfig.qa.showCarbEntries"
        static let qaShowBolusHistoryKey = "AIInsightsConfig.qa.showBolusHistory"
        static let qaCustomPromptKey = "AIInsightsConfig.qa.customPrompt"
        // Why High/Low Settings Keys
        static let whlHighThresholdKey = "AIInsightsConfig.whl.highThreshold"
        static let whlLowThresholdKey = "AIInsightsConfig.whl.lowThreshold"
        static let whlAnalysisHoursKey = "AIInsightsConfig.whl.analysisHours"
        static let whlCustomPromptKey = "AIInsightsConfig.whl.customPrompt"
        // Photo Carb Estimation Settings Keys
        static let photoCustomPromptKey = "AIInsightsConfig.photo.customPrompt"
        static let photoDefaultPortionKey = "AIInsightsConfig.photo.defaultPortion"
    }

    /// Default AI prompt for doctor visit report
    static let defaultDoctorReportPrompt = """
Please analyze this data and provide a comprehensive report for discussion with my healthcare provider. Include:

### 📊 **Executive Summary**
- Overall diabetes management assessment
- Key metrics vs targets (TIR goal >70%, TBR <4%, CV <36%)

### 📈 **Trend Analysis**
- Compare metrics across timeframes (improving, stable, or declining)
- Identify any concerning trends

### 🕐 **Time-of-Day Patterns**
- Morning/dawn phenomenon analysis
- Post-meal patterns
- Overnight control
- Any consistent problem times

### ⚙️ **Settings Recommendations**
- Specific basal rate adjustments (time and amount)
- Carb ratio changes needed
- ISF modifications
- Target range considerations

### ⚠️ **Safety Concerns**
- Hypoglycemia patterns and prevention
- Severe hyperglycemia events
- Glycemic variability concerns

### 💡 **Discussion Points for Provider**
- Priority items to address
- Questions to ask
- Suggested next steps

Format this professionally for sharing with an endocrinologist or diabetes care team.
"""

    /// Default AI prompt for quick analysis
    static let defaultQuickAnalysisPrompt = """
Please provide a quick analysis using these sections:
📊 **Overview** - Brief summary of glucose control
🔍 **Key Patterns** - Notable trends you observe
⚠️ **Concerns** - Any issues needing attention
💡 **Quick Tip** - One actionable suggestion
"""

    /// Default AI prompt for Why High/Low analysis
    static let defaultWhyHighLowPrompt = """
Please analyze why my blood glucose is currently out of range.

Provide:
1. **Probable Cause**: The most likely reason (be specific about timing and amounts)
2. **Contributing Factors**: Any secondary factors
3. **Suggestion**: A conservative recommendation if appropriate

Keep the response concise and actionable. Focus on the most likely explanation.
"""

    /// Default AI prompt for photo carb estimation
    static let defaultPhotoCarbPrompt = """
Analyze this food photo and estimate the carbohydrate content.

Provide:
1. **Itemized Breakdown**: List each food item with estimated carbs
   - Format: "Food item (portion): ~Xg"
2. **Total Estimate**: Sum of all items (single number, not a range)
3. **Confidence Level**: Low / Medium / High
4. **Notes**: Any assumptions made

Be conservative when uncertain. Round to nearest 5g.
"""

    /// Analysis hours options for Why High/Low
    enum AnalysisHours: Int, CaseIterable, Identifiable {
        case two = 2
        case four = 4
        case six = 6

        var id: Int { rawValue }

        var displayName: String {
            "\(rawValue) Hours"
        }
    }

    /// Portion size options for photo carb estimation
    enum PortionSize: String, CaseIterable, Identifiable {
        case small
        case standard
        case large

        var id: String { rawValue }

        var displayName: String {
            rawValue.capitalized
        }
    }

    /// Result from photo carb estimation
    struct CarbEstimateResult {
        let items: [CarbItem]
        let totalCarbs: Decimal
        let confidence: ConfidenceLevel
        let notes: String?
        let rawResponse: String

        struct CarbItem: Identifiable {
            let id = UUID()
            let name: String
            let portion: String
            let carbs: Decimal
        }

        enum ConfidenceLevel: String {
            case low = "Low"
            case medium = "Medium"
            case high = "High"

            var color: String {
                switch self {
                case .low: return "red"
                case .medium: return "orange"
                case .high: return "green"
                }
            }
        }
    }

    struct ChatMessage: Identifiable, Equatable {
        let id = UUID()
        let role: String
        let content: String
        let timestamp: Date

        var isUser: Bool { role == "user" }
    }

    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var keychain: Keychain!
        @Injected() private var storage: FileStorage!

        private let coredataContext = CoreDataStack.shared.newTaskContext()
        private let claudeService = ClaudeAPIService()

        // API Key
        @Published var apiKey = ""
        @Published var isAPIKeyConfigured = false
        @Published var isAPIKeyVisible = false

        // Quick Analysis
        @Published var quickAnalysisResult = ""
        @Published var isAnalyzing = false
        @Published var analysisError: String?

        // Quick Analysis Settings
        @Published var qaTimePeriod: TimePeriod = .sevenDays
        @Published var qaShowCarbRatios = true
        @Published var qaShowISF = true
        @Published var qaShowBasalRates = true
        @Published var qaShowTargets = true
        @Published var qaShowInsulinSettings = true
        @Published var qaShowStatistics = true
        @Published var qaShowLoopData = true
        @Published var qaShowCarbEntries = true
        @Published var qaShowBolusHistory = true
        @Published var qaCustomPrompt: String = AIInsightsConfig.defaultQuickAnalysisPrompt

        // Chat
        @Published var chatMessages: [ChatMessage] = []
        @Published var currentMessage = ""
        @Published var isSendingMessage = false

        // Weekly Report
        @Published var weeklyReport = ""
        @Published var isGeneratingReport = false

        // Doctor Visit Report
        @Published var doctorVisitReport = ""
        @Published var isGeneratingDoctorReport = false
        @Published var doctorReportPDFData: Data?

        // Quick Analysis PDF (for saving)
        @Published var quickAnalysisPDFData: Data?

        // Weekly Report PDF (for saving)
        @Published var weeklyReportPDFData: Data?

        // Saved Reports
        @Published var savedReports: [SavedReportsManager.SavedReport] = []

        // Doctor Report Settings
        @Published var drTimePeriod: TimePeriod = .thirtyDays
        @Published var drShowCarbRatios = true
        @Published var drShowISF = true
        @Published var drShowBasalRates = true
        @Published var drShowTargets = true
        @Published var drShowInsulinSettings = true
        @Published var drShowStatistics = true
        @Published var drShowLoopData = true
        @Published var drShowCarbEntries = true
        @Published var drShowBolusHistory = true
        @Published var drCustomPrompt: String = AIInsightsConfig.defaultDoctorReportPrompt

        // Why High/Low Analysis
        @Published var whyHighLowResult = ""
        @Published var isAnalyzingWhyHighLow = false
        @Published var whyHighLowError: String?
        @Published var whyHighLowPDFData: Data?

        // Why High/Low Settings
        @Published var whlHighThreshold: Decimal = 180
        @Published var whlLowThreshold: Decimal = 70
        @Published var whlAnalysisHours: AnalysisHours = .four
        @Published var whlCustomPrompt: String = AIInsightsConfig.defaultWhyHighLowPrompt

        // Photo Carb Estimation
        @Published var carbEstimateResult: CarbEstimateResult?
        @Published var isEstimatingCarbs = false
        @Published var carbEstimateError: String?
        @Published var selectedFoodImage: UIImage?
        @Published var foodDescription: String = ""

        // Photo Carb Settings
        @Published var photoCustomPrompt: String = AIInsightsConfig.defaultPhotoCarbPrompt
        @Published var photoDefaultPortion: PortionSize = .standard

        // Settings for context
        @Published var units: GlucoseUnits = .mgdL

        override func subscribe() {
            // Load API key from keychain
            if let storedKey = keychain.getValue(String.self, forKey: Config.apiKeyKey) {
                apiKey = storedKey
                isAPIKeyConfigured = !storedKey.isEmpty
            }

            // Get current units
            units = settingsManager.settings.units

            // Load settings
            loadDoctorReportSettings()
            loadQuickAnalysisSettings()
            loadWhyHighLowSettings()
            loadPhotoCarbSettings()

            // Load saved reports
            loadSavedReports()
        }

        func loadSavedReports() {
            savedReports = SavedReportsManager.shared.getSavedReports()
        }

        func deleteSavedReport(_ report: SavedReportsManager.SavedReport) {
            SavedReportsManager.shared.deleteReport(report)
            loadSavedReports()
        }

        private func loadDoctorReportSettings() {
            let defaults = UserDefaults.standard
            let keys = defaults.dictionaryRepresentation().keys

            // Load time period (default to 30 days)
            if let savedPeriod = defaults.string(forKey: Config.drTimePeriodKey),
               let period = TimePeriod(rawValue: savedPeriod) {
                drTimePeriod = period
            } else {
                drTimePeriod = .thirtyDays
            }

            // Load toggles with default true if not set
            drShowCarbRatios = keys.contains(Config.drShowCarbRatiosKey) ? defaults.bool(forKey: Config.drShowCarbRatiosKey) : true
            drShowISF = keys.contains(Config.drShowISFKey) ? defaults.bool(forKey: Config.drShowISFKey) : true
            drShowBasalRates = keys.contains(Config.drShowBasalRatesKey) ? defaults.bool(forKey: Config.drShowBasalRatesKey) : true
            drShowTargets = keys.contains(Config.drShowTargetsKey) ? defaults.bool(forKey: Config.drShowTargetsKey) : true
            drShowInsulinSettings = keys.contains(Config.drShowInsulinSettingsKey) ? defaults.bool(forKey: Config.drShowInsulinSettingsKey) : true
            drShowStatistics = keys.contains(Config.drShowStatisticsKey) ? defaults.bool(forKey: Config.drShowStatisticsKey) : true
            drShowLoopData = keys.contains(Config.drShowLoopDataKey) ? defaults.bool(forKey: Config.drShowLoopDataKey) : true
            drShowCarbEntries = keys.contains(Config.drShowCarbEntriesKey) ? defaults.bool(forKey: Config.drShowCarbEntriesKey) : true
            drShowBolusHistory = keys.contains(Config.drShowBolusHistoryKey) ? defaults.bool(forKey: Config.drShowBolusHistoryKey) : true

            // Load custom prompt, default to the standard prompt
            if let savedPrompt = defaults.string(forKey: Config.drCustomPromptKey), !savedPrompt.isEmpty {
                drCustomPrompt = savedPrompt
            } else {
                drCustomPrompt = AIInsightsConfig.defaultDoctorReportPrompt
            }
        }

        private func loadQuickAnalysisSettings() {
            let defaults = UserDefaults.standard
            let keys = defaults.dictionaryRepresentation().keys

            // Load time period (default to 7 days)
            if let savedPeriod = defaults.string(forKey: Config.qaTimePeriodKey),
               let period = TimePeriod(rawValue: savedPeriod) {
                qaTimePeriod = period
            } else {
                qaTimePeriod = .sevenDays
            }

            // Load toggles with default true if not set
            qaShowCarbRatios = keys.contains(Config.qaShowCarbRatiosKey) ? defaults.bool(forKey: Config.qaShowCarbRatiosKey) : true
            qaShowISF = keys.contains(Config.qaShowISFKey) ? defaults.bool(forKey: Config.qaShowISFKey) : true
            qaShowBasalRates = keys.contains(Config.qaShowBasalRatesKey) ? defaults.bool(forKey: Config.qaShowBasalRatesKey) : true
            qaShowTargets = keys.contains(Config.qaShowTargetsKey) ? defaults.bool(forKey: Config.qaShowTargetsKey) : true
            qaShowInsulinSettings = keys.contains(Config.qaShowInsulinSettingsKey) ? defaults.bool(forKey: Config.qaShowInsulinSettingsKey) : true
            qaShowStatistics = keys.contains(Config.qaShowStatisticsKey) ? defaults.bool(forKey: Config.qaShowStatisticsKey) : true
            qaShowLoopData = keys.contains(Config.qaShowLoopDataKey) ? defaults.bool(forKey: Config.qaShowLoopDataKey) : true
            qaShowCarbEntries = keys.contains(Config.qaShowCarbEntriesKey) ? defaults.bool(forKey: Config.qaShowCarbEntriesKey) : true
            qaShowBolusHistory = keys.contains(Config.qaShowBolusHistoryKey) ? defaults.bool(forKey: Config.qaShowBolusHistoryKey) : true

            // Load custom prompt, default to the standard prompt
            if let savedPrompt = defaults.string(forKey: Config.qaCustomPromptKey), !savedPrompt.isEmpty {
                qaCustomPrompt = savedPrompt
            } else {
                qaCustomPrompt = AIInsightsConfig.defaultQuickAnalysisPrompt
            }
        }

        func saveDoctorReportSettings() {
            let defaults = UserDefaults.standard
            defaults.set(drTimePeriod.rawValue, forKey: Config.drTimePeriodKey)
            defaults.set(drShowCarbRatios, forKey: Config.drShowCarbRatiosKey)
            defaults.set(drShowISF, forKey: Config.drShowISFKey)
            defaults.set(drShowBasalRates, forKey: Config.drShowBasalRatesKey)
            defaults.set(drShowTargets, forKey: Config.drShowTargetsKey)
            defaults.set(drShowInsulinSettings, forKey: Config.drShowInsulinSettingsKey)
            defaults.set(drShowStatistics, forKey: Config.drShowStatisticsKey)
            defaults.set(drShowLoopData, forKey: Config.drShowLoopDataKey)
            defaults.set(drShowCarbEntries, forKey: Config.drShowCarbEntriesKey)
            defaults.set(drShowBolusHistory, forKey: Config.drShowBolusHistoryKey)
            defaults.set(drCustomPrompt, forKey: Config.drCustomPromptKey)
        }

        func saveQuickAnalysisSettings() {
            let defaults = UserDefaults.standard
            defaults.set(qaTimePeriod.rawValue, forKey: Config.qaTimePeriodKey)
            defaults.set(qaShowCarbRatios, forKey: Config.qaShowCarbRatiosKey)
            defaults.set(qaShowISF, forKey: Config.qaShowISFKey)
            defaults.set(qaShowBasalRates, forKey: Config.qaShowBasalRatesKey)
            defaults.set(qaShowTargets, forKey: Config.qaShowTargetsKey)
            defaults.set(qaShowInsulinSettings, forKey: Config.qaShowInsulinSettingsKey)
            defaults.set(qaShowStatistics, forKey: Config.qaShowStatisticsKey)
            defaults.set(qaShowLoopData, forKey: Config.qaShowLoopDataKey)
            defaults.set(qaShowCarbEntries, forKey: Config.qaShowCarbEntriesKey)
            defaults.set(qaShowBolusHistory, forKey: Config.qaShowBolusHistoryKey)
            defaults.set(qaCustomPrompt, forKey: Config.qaCustomPromptKey)
        }

        func resetDoctorReportPrompt() {
            drCustomPrompt = AIInsightsConfig.defaultDoctorReportPrompt
            UserDefaults.standard.set(drCustomPrompt, forKey: Config.drCustomPromptKey)
        }

        func resetQuickAnalysisPrompt() {
            qaCustomPrompt = AIInsightsConfig.defaultQuickAnalysisPrompt
            UserDefaults.standard.set(qaCustomPrompt, forKey: Config.qaCustomPromptKey)
        }

        private func loadWhyHighLowSettings() {
            let defaults = UserDefaults.standard

            // Load thresholds (default: 180 high, 70 low)
            if let highThreshold = defaults.object(forKey: Config.whlHighThresholdKey) as? Double {
                whlHighThreshold = Decimal(highThreshold)
            } else {
                whlHighThreshold = 180
            }

            if let lowThreshold = defaults.object(forKey: Config.whlLowThresholdKey) as? Double {
                whlLowThreshold = Decimal(lowThreshold)
            } else {
                whlLowThreshold = 70
            }

            // Load analysis hours (default: 4 hours)
            if let hours = defaults.object(forKey: Config.whlAnalysisHoursKey) as? Int,
               let analysisHours = AnalysisHours(rawValue: hours) {
                whlAnalysisHours = analysisHours
            } else {
                whlAnalysisHours = .four
            }

            // Load custom prompt
            if let savedPrompt = defaults.string(forKey: Config.whlCustomPromptKey), !savedPrompt.isEmpty {
                whlCustomPrompt = savedPrompt
            } else {
                whlCustomPrompt = AIInsightsConfig.defaultWhyHighLowPrompt
            }
        }

        func saveWhyHighLowSettings() {
            let defaults = UserDefaults.standard
            defaults.set(Double(truncating: whlHighThreshold as NSNumber), forKey: Config.whlHighThresholdKey)
            defaults.set(Double(truncating: whlLowThreshold as NSNumber), forKey: Config.whlLowThresholdKey)
            defaults.set(whlAnalysisHours.rawValue, forKey: Config.whlAnalysisHoursKey)
            defaults.set(whlCustomPrompt, forKey: Config.whlCustomPromptKey)
        }

        func resetWhyHighLowPrompt() {
            whlCustomPrompt = AIInsightsConfig.defaultWhyHighLowPrompt
            UserDefaults.standard.set(whlCustomPrompt, forKey: Config.whlCustomPromptKey)
        }

        private func loadPhotoCarbSettings() {
            let defaults = UserDefaults.standard

            // Load custom prompt
            if let savedPrompt = defaults.string(forKey: Config.photoCustomPromptKey), !savedPrompt.isEmpty {
                photoCustomPrompt = savedPrompt
            } else {
                photoCustomPrompt = AIInsightsConfig.defaultPhotoCarbPrompt
            }

            // Load default portion size
            if let savedPortion = defaults.string(forKey: Config.photoDefaultPortionKey),
               let portion = PortionSize(rawValue: savedPortion) {
                photoDefaultPortion = portion
            } else {
                photoDefaultPortion = .standard
            }
        }

        func savePhotoCarbSettings() {
            let defaults = UserDefaults.standard
            defaults.set(photoCustomPrompt, forKey: Config.photoCustomPromptKey)
            defaults.set(photoDefaultPortion.rawValue, forKey: Config.photoDefaultPortionKey)
        }

        func resetPhotoCarbPrompt() {
            photoCustomPrompt = AIInsightsConfig.defaultPhotoCarbPrompt
            UserDefaults.standard.set(photoCustomPrompt, forKey: Config.photoCustomPromptKey)
        }

        // MARK: - API Key Management

        func saveAPIKey() {
            keychain.setValue(apiKey, forKey: Config.apiKeyKey)
            isAPIKeyConfigured = !apiKey.isEmpty
        }

        func deleteAPIKey() {
            keychain.removeObject(forKey: Config.apiKeyKey)
            apiKey = ""
            isAPIKeyConfigured = false
        }

        func toggleAPIKeyVisibility() {
            isAPIKeyVisible.toggle()
        }

        // MARK: - Data Export

        private func exportData(days: Int) async throws -> HealthDataExporter.ExportedData {
            let exporter = HealthDataExporter(context: coredataContext)

            // Get current settings
            let settings = settingsManager.settings
            let preferences = settingsManager.preferences
            let pumpSettings = settingsManager.pumpSettings

            // Fetch detailed schedules from file storage
            let carbRatioSchedule = await fetchCarbRatios()
            let isfSchedule = await fetchISFSchedule()
            let basalSchedule = await fetchBasalSchedule()
            let targetSchedule = await fetchTargetSchedule()

            let lowTarget = settings.units == .mgdL ? Int(settings.low) : Int(settings.low * 18)
            let highTarget = settings.units == .mgdL ? Int(settings.high) : Int(settings.high * 18)

            return try await exporter.exportData(
                days: days,
                units: settings.units.rawValue,
                targetLow: lowTarget,
                targetHigh: highTarget,
                maxIOB: preferences.maxIOB,
                maxBolus: pumpSettings.maxBolus,
                dia: pumpSettings.insulinActionCurve,
                carbRatioSchedule: carbRatioSchedule,
                isfSchedule: isfSchedule,
                basalSchedule: basalSchedule,
                targetSchedule: targetSchedule
            )
        }

        private func fetchCarbRatios() async -> [(time: String, ratio: Decimal)] {
            guard let carbRatios = await storage.retrieveAsync(OpenAPS.Settings.carbRatios, as: CarbRatios.self) else {
                return []
            }
            return carbRatios.schedule.map { (time: $0.start, ratio: $0.ratio) }
        }

        private func fetchISFSchedule() async -> [(time: String, sensitivity: Decimal)] {
            guard let isf = await storage.retrieveAsync(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self) else {
                return []
            }
            return isf.sensitivities.map { (time: $0.start, sensitivity: $0.sensitivity) }
        }

        private func fetchBasalSchedule() async -> [(time: String, rate: Decimal)] {
            guard let basals = await storage.retrieveAsync(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self) else {
                return []
            }
            return basals.map { (time: $0.start, rate: $0.rate) }
        }

        private func fetchTargetSchedule() async -> [(time: String, low: Decimal, high: Decimal)] {
            guard let targets = await storage.retrieveAsync(OpenAPS.Settings.bgTargets, as: BGTargets.self) else {
                return []
            }
            return targets.targets.map { (time: $0.start, low: $0.low, high: $0.high) }
        }

        // MARK: - Quick Analysis

        @MainActor
        func runQuickAnalysis() async {
            guard isAPIKeyConfigured else {
                analysisError = "Please configure your Claude API key first."
                return
            }

            isAnalyzing = true
            analysisError = nil
            quickAnalysisResult = ""

            do {
                let data = try await exportData(days: qaTimePeriod.days)
                let exporter = HealthDataExporter(context: coredataContext)

                // Build settings from current Quick Analysis preferences
                let qaSettings = HealthDataExporter.QuickAnalysisSettings(
                    showCarbRatios: qaShowCarbRatios,
                    showISF: qaShowISF,
                    showBasalRates: qaShowBasalRates,
                    showTargets: qaShowTargets,
                    showInsulinSettings: qaShowInsulinSettings,
                    showStatistics: qaShowStatistics,
                    showLoopData: qaShowLoopData,
                    showCarbEntries: qaShowCarbEntries,
                    showBolusHistory: qaShowBolusHistory,
                    customPrompt: qaCustomPrompt,
                    days: qaTimePeriod.days
                )

                let prompt = exporter.formatForPrompt(data, analysisType: .quick(settings: qaSettings))

                let result = try await claudeService.analyze(prompt: prompt, apiKey: apiKey)
                quickAnalysisResult = result

                // Generate PDF and auto-save
                if let pdfData = generatePDF(
                    from: result,
                    title: "Quick Analysis Report",
                    timePeriod: qaTimePeriod.displayName
                ) {
                    quickAnalysisPDFData = pdfData
                    SavedReportsManager.shared.saveReport(
                        type: .quickAnalysis,
                        content: result,
                        timePeriod: qaTimePeriod.displayName,
                        pdfData: pdfData
                    )
                    loadSavedReports()
                }
            } catch {
                analysisError = error.localizedDescription
            }

            isAnalyzing = false
        }

        // MARK: - Chat

        @MainActor
        func sendChatMessage() async {
            guard isAPIKeyConfigured else {
                analysisError = "Please configure your Claude API key first."
                return
            }

            let userMessage = currentMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !userMessage.isEmpty else { return }

            // Add user message to chat
            chatMessages.append(ChatMessage(role: "user", content: userMessage, timestamp: Date()))
            currentMessage = ""
            isSendingMessage = true

            do {
                // Build messages array with context
                var apiMessages: [ClaudeAPIService.Message] = []

                // If this is the first message, include data context (use 7 days for chat)
                if chatMessages.count == 1 {
                    let data = try await exportData(days: 7)
                    let exporter = HealthDataExporter(context: coredataContext)
                    let context = exporter.formatForPrompt(data, analysisType: .chat)
                    apiMessages.append(ClaudeAPIService.Message(role: "user", content: context))
                    apiMessages.append(ClaudeAPIService.Message(
                        role: "assistant",
                        content: "I've reviewed your glucose data. I can see your settings, statistics, and trends. What would you like to know?"
                    ))
                }

                // Add recent chat history (last 10 messages for context)
                let recentMessages = chatMessages.suffix(10)
                for msg in recentMessages {
                    apiMessages.append(ClaudeAPIService.Message(role: msg.role, content: msg.content))
                }

                let response = try await claudeService.sendMessage(messages: apiMessages, apiKey: apiKey)
                chatMessages.append(ChatMessage(role: "assistant", content: response, timestamp: Date()))
            } catch {
                chatMessages.append(ChatMessage(
                    role: "assistant",
                    content: "Sorry, I encountered an error: \(error.localizedDescription)",
                    timestamp: Date()
                ))
            }

            isSendingMessage = false
        }

        func clearChat() {
            chatMessages.removeAll()
        }

        // MARK: - Why High/Low Analysis

        @MainActor
        func analyzeWhyHighLow(
            currentBG: Decimal,
            bgTrend: String,
            currentIOB: Decimal,
            currentCOB: Int,
            isHigh: Bool
        ) async {
            guard isAPIKeyConfigured else {
                whyHighLowError = "Please configure your Claude API key first."
                return
            }

            isAnalyzingWhyHighLow = true
            whyHighLowError = nil
            whyHighLowResult = ""

            do {
                let exporter = HealthDataExporter(context: coredataContext)

                // Get current settings
                let settings = settingsManager.settings
                let carbRatios = await fetchCarbRatios()
                let isfSchedule = await fetchISFSchedule()
                let basalSchedule = await fetchBasalSchedule()

                // Get current values based on time of day
                let currentCR = getCurrentScheduleValue(from: carbRatios.map { ($0.time, $0.ratio) }) ?? 10
                let currentISF = getCurrentScheduleValue(from: isfSchedule.map { ($0.time, $0.sensitivity) }) ?? 50
                let currentBasal = getCurrentScheduleValue(from: basalSchedule.map { ($0.time, $0.rate) }) ?? 1

                let lowTarget = settings.units == .mgdL ? Int(settings.low) : Int(settings.low * 18)
                let highTarget = settings.units == .mgdL ? Int(settings.high) : Int(settings.high * 18)

                // Export recent data
                let data = try await exporter.exportDataForHours(
                    hours: whlAnalysisHours.rawValue,
                    units: settings.units.rawValue,
                    currentISF: currentISF,
                    currentCR: currentCR,
                    currentBasalRate: currentBasal,
                    targetLow: lowTarget,
                    targetHigh: highTarget
                )

                // Build settings for prompt
                let whlSettings = HealthDataExporter.WhyHighLowSettings(
                    currentBG: currentBG,
                    bgTrend: bgTrend,
                    currentIOB: currentIOB,
                    currentCOB: currentCOB,
                    isHigh: isHigh,
                    analysisHours: whlAnalysisHours.rawValue,
                    customPrompt: whlCustomPrompt
                )

                // Format prompt
                let prompt = exporter.formatWhyHighLowPrompt(data, settings: whlSettings)

                // Call Claude API
                let result = try await claudeService.analyze(prompt: prompt, apiKey: apiKey)
                whyHighLowResult = result

                // Generate PDF
                let title = isHigh ? "Why Am I High?" : "Why Am I Low?"
                if let pdfData = generatePDF(
                    from: result,
                    title: title,
                    timePeriod: "\(whlAnalysisHours.rawValue) Hours"
                ) {
                    whyHighLowPDFData = pdfData
                }
            } catch {
                whyHighLowError = error.localizedDescription
            }

            isAnalyzingWhyHighLow = false
        }

        /// Get the current value from a time-based schedule
        private func getCurrentScheduleValue(from schedule: [(String, Decimal)]) -> Decimal? {
            guard !schedule.isEmpty else { return nil }

            let now = Date()
            let calendar = Calendar.current
            let currentMinutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)

            // Find the applicable schedule entry
            var result: Decimal = schedule.first!.1

            for (timeString, value) in schedule {
                let components = timeString.split(separator: ":")
                if components.count >= 2,
                   let hour = Int(components[0]),
                   let minute = Int(components[1]) {
                    let scheduleMinutes = hour * 60 + minute
                    if scheduleMinutes <= currentMinutes {
                        result = value
                    }
                }
            }

            return result
        }

        func clearWhyHighLowResult() {
            whyHighLowResult = ""
            whyHighLowError = nil
            whyHighLowPDFData = nil
        }

        // MARK: - Photo Carb Estimation

        @MainActor
        func estimateCarbsFromPhoto() async {
            guard isAPIKeyConfigured else {
                carbEstimateError = "Please configure your Claude API key first."
                return
            }

            guard let image = selectedFoodImage else {
                carbEstimateError = "Please select or take a photo first."
                return
            }

            isEstimatingCarbs = true
            carbEstimateError = nil
            carbEstimateResult = nil

            do {
                let result = try await claudeService.estimateCarbs(
                    from: image,
                    description: foodDescription.isEmpty ? nil : foodDescription,
                    customPrompt: photoCustomPrompt,
                    defaultPortion: photoDefaultPortion.displayName,
                    apiKey: apiKey
                )

                // Parse the result to extract total carbs
                let parsedResult = parseCarbEstimateResponse(result)
                carbEstimateResult = parsedResult
            } catch {
                carbEstimateError = error.localizedDescription
            }

            isEstimatingCarbs = false
        }

        /// Parse the AI response to extract carb estimate details
        private func parseCarbEstimateResponse(_ response: String) -> CarbEstimateResult {
            var items: [CarbEstimateResult.CarbItem] = []
            var totalCarbs: Decimal = 0
            var confidence: CarbEstimateResult.ConfidenceLevel = .medium
            var notes: String?

            let lines = response.components(separatedBy: "\n")

            for line in lines {
                // Look for food items with carb estimates (e.g., "🍽️ Pasta (1 cup): ~35g" or "Pasta: ~35g")
                if let match = extractCarbItem(from: line) {
                    items.append(match)
                }

                // Look for total (e.g., "Total: ~55g" or "**Total Estimate: ~55g**")
                let lowercaseLine = line.lowercased()
                if lowercaseLine.contains("total") {
                    if let carbValue = extractCarbValue(from: line) {
                        totalCarbs = carbValue
                    }
                }

                // Look for confidence level
                if lowercaseLine.contains("confidence") {
                    if lowercaseLine.contains("high") {
                        confidence = .high
                    } else if lowercaseLine.contains("low") {
                        confidence = .low
                    } else {
                        confidence = .medium
                    }
                }

                // Look for notes/assumptions
                if lowercaseLine.contains("note") || lowercaseLine.contains("assumption") {
                    if notes == nil {
                        notes = line
                    } else {
                        notes! += "\n" + line
                    }
                }
            }

            // If we didn't find a total but have items, sum them up
            if totalCarbs == 0 && !items.isEmpty {
                totalCarbs = items.reduce(0) { $0 + $1.carbs }
            }

            return CarbEstimateResult(
                items: items,
                totalCarbs: totalCarbs,
                confidence: confidence,
                notes: notes,
                rawResponse: response
            )
        }

        /// Extract a carb item from a line like "🍽️ Pasta (1 cup): ~35g"
        private func extractCarbItem(from line: String) -> CarbEstimateResult.CarbItem? {
            // Skip lines that are headers or totals
            let lowercaseLine = line.lowercased()
            if lowercaseLine.contains("total") || lowercaseLine.contains("confidence") ||
               lowercaseLine.contains("note") || lowercaseLine.contains("assumption") {
                return nil
            }

            // Look for carb value patterns like "~35g", "35g", "35 g"
            guard let carbValue = extractCarbValue(from: line), carbValue > 0 else {
                return nil
            }

            // Extract the food name (everything before the carb value)
            var foodName = line

            // Remove common prefixes
            let prefixes = ["🍽️", "•", "-", "*", "**"]
            for prefix in prefixes {
                foodName = foodName.trimmingCharacters(in: .whitespaces)
                if foodName.hasPrefix(prefix) {
                    foodName = String(foodName.dropFirst(prefix.count))
                }
            }

            // Remove the carb value from the name
            if let range = foodName.range(of: "~?\\d+\\s*g", options: .regularExpression) {
                foodName = String(foodName[..<range.lowerBound])
            }

            // Clean up
            foodName = foodName.trimmingCharacters(in: .whitespaces)
            foodName = foodName.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            foodName = foodName.trimmingCharacters(in: .whitespaces)

            // Extract portion if present (in parentheses)
            var portion = ""
            if let openParen = foodName.firstIndex(of: "("),
               let closeParen = foodName.firstIndex(of: ")") {
                portion = String(foodName[foodName.index(after: openParen)..<closeParen])
                foodName = String(foodName[..<openParen]).trimmingCharacters(in: .whitespaces)
            }

            guard !foodName.isEmpty else { return nil }

            return CarbEstimateResult.CarbItem(
                name: foodName,
                portion: portion,
                carbs: carbValue
            )
        }

        /// Extract a carb value from a string like "~35g" or "35 g"
        private func extractCarbValue(from string: String) -> Decimal? {
            // Pattern to match carb values: "~35g", "35g", "35 g", "~35 g"
            let pattern = "~?(\\d+)\\s*g"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                return nil
            }

            let range = NSRange(string.startIndex..<string.endIndex, in: string)
            guard let match = regex.firstMatch(in: string, options: [], range: range) else {
                return nil
            }

            guard let valueRange = Range(match.range(at: 1), in: string) else {
                return nil
            }

            let valueString = String(string[valueRange])
            guard let intValue = Int(valueString) else {
                return nil
            }

            return Decimal(intValue)
        }

        func clearCarbEstimate() {
            carbEstimateResult = nil
            carbEstimateError = nil
            selectedFoodImage = nil
            foodDescription = ""
        }

        // MARK: - Weekly Report

        @MainActor
        func generateWeeklyReport() async {
            guard isAPIKeyConfigured else {
                analysisError = "Please configure your Claude API key first."
                return
            }

            isGeneratingReport = true
            analysisError = nil
            weeklyReport = ""

            do {
                let data = try await exportData(days: 7)
                let exporter = HealthDataExporter(context: coredataContext)
                let prompt = exporter.formatForPrompt(data, analysisType: .weeklyReport)

                let result = try await claudeService.analyze(prompt: prompt, apiKey: apiKey)
                weeklyReport = result

                // Generate PDF and auto-save
                if let pdfData = generatePDF(
                    from: result,
                    title: "Weekly Report",
                    timePeriod: "7 Days"
                ) {
                    weeklyReportPDFData = pdfData
                    SavedReportsManager.shared.saveReport(
                        type: .weeklyReport,
                        content: result,
                        timePeriod: "7 Days",
                        pdfData: pdfData
                    )
                    loadSavedReports()
                }
            } catch {
                analysisError = error.localizedDescription
            }

            isGeneratingReport = false
        }

        func getShareableReport() -> String {
            guard !weeklyReport.isEmpty else { return "" }

            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .long

            return """
            Trio AI Weekly Report
            Generated: \(dateFormatter.string(from: Date()))

            \(weeklyReport)

            ---
            This report was generated by AI for educational purposes.
            Always consult your healthcare provider before making treatment changes.
            """
        }

        // MARK: - Doctor Visit Report

        @MainActor
        func generateDoctorVisitReport() async {
            guard isAPIKeyConfigured else {
                analysisError = "Please configure your Claude API key first."
                return
            }

            isGeneratingDoctorReport = true
            analysisError = nil
            doctorVisitReport = ""
            doctorReportPDFData = nil

            do {
                let data = try await exportData(days: drTimePeriod.days)
                let exporter = HealthDataExporter(context: coredataContext)

                // Build settings from current preferences
                let reportSettings = HealthDataExporter.DoctorReportSettings(
                    showCarbRatios: drShowCarbRatios,
                    showISF: drShowISF,
                    showBasalRates: drShowBasalRates,
                    showTargets: drShowTargets,
                    showInsulinSettings: drShowInsulinSettings,
                    showStatistics: drShowStatistics,
                    showLoopData: drShowLoopData,
                    showCarbEntries: drShowCarbEntries,
                    showBolusHistory: drShowBolusHistory,
                    customPrompt: drCustomPrompt,
                    days: drTimePeriod.days
                )

                let prompt = exporter.formatForPrompt(data, analysisType: .doctorVisit(settings: reportSettings))

                let result = try await claudeService.analyze(prompt: prompt, apiKey: apiKey)
                doctorVisitReport = result

                // Generate PDF and auto-save
                if let pdfData = generatePDF(
                    from: result,
                    title: "Doctor Visit Report",
                    timePeriod: drTimePeriod.displayName
                ) {
                    doctorReportPDFData = pdfData
                    SavedReportsManager.shared.saveReport(
                        type: .doctorReport,
                        content: result,
                        timePeriod: drTimePeriod.displayName,
                        pdfData: pdfData
                    )
                    loadSavedReports()
                }
            } catch {
                analysisError = error.localizedDescription
            }

            isGeneratingDoctorReport = false
        }

        func getShareableDoctorReport() -> String {
            guard !doctorVisitReport.isEmpty else { return "" }

            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .long

            return """
            ═══════════════════════════════════════════════════════════════
            TRIO DIABETES MANAGEMENT REPORT - FOR HEALTHCARE PROVIDER REVIEW
            ═══════════════════════════════════════════════════════════════

            Generated: \(dateFormatter.string(from: Date()))
            Data Period: \(drTimePeriod.displayName)

            \(doctorVisitReport)

            ═══════════════════════════════════════════════════════════════
            DISCLAIMER
            ═══════════════════════════════════════════════════════════════
            This report was generated by AI analysis of glucose and treatment data.
            It is intended to facilitate discussion with healthcare providers and
            should not replace professional medical advice.

            Always consult your healthcare provider before making treatment changes.

            Generated by Trio with AI Insights
            ═══════════════════════════════════════════════════════════════
            """
        }

        // MARK: - PDF Generation with Multi-Page Support

        private func generatePDF(
            from report: String,
            title: String,
            timePeriod: String
        ) -> Data? {
            let pageWidth: CGFloat = 612 // Letter size
            let pageHeight: CGFloat = 792
            let margin: CGFloat = 50
            let contentWidth = pageWidth - 2 * margin
            let headerHeight: CGFloat = 80 // Space for title, date, and separator

            let pdfMetaData = [
                kCGPDFContextCreator: "Trio AI Insights",
                kCGPDFContextAuthor: "Trio App",
                kCGPDFContextTitle: title
            ]

            let format = UIGraphicsPDFRendererFormat()
            format.documentInfo = pdfMetaData as [String: Any]

            let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
            let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

            // Parse markdown to attributed string
            let attributedContent = MarkdownParser.parseToNSAttributedString(report, style: .pdf)

            // Calculate total content height
            let contentRect = CGRect(x: 0, y: 0, width: contentWidth, height: .greatestFiniteMagnitude)
            let boundingRect = attributedContent.boundingRect(
                with: contentRect.size,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            let totalContentHeight = boundingRect.height

            // Calculate available height per page
            let firstPageContentHeight = pageHeight - margin - headerHeight - margin
            let subsequentPageContentHeight = pageHeight - margin - margin

            let data = renderer.pdfData { context in
                var currentY: CGFloat = 0
                var remainingHeight = totalContentHeight
                var isFirstPage = true
                var pageNumber = 1

                // Create text storage for drawing
                let textStorage = NSTextStorage(attributedString: attributedContent)
                let layoutManager = NSLayoutManager()
                textStorage.addLayoutManager(layoutManager)

                let textContainer = NSTextContainer(size: CGSize(width: contentWidth, height: .greatestFiniteMagnitude))
                textContainer.lineFragmentPadding = 0
                layoutManager.addTextContainer(textContainer)

                // Force layout
                layoutManager.ensureLayout(for: textContainer)

                var glyphRange = NSRange(location: 0, length: 0)
                var drawnGlyphRange = NSRange(location: 0, length: 0)

                while drawnGlyphRange.location + drawnGlyphRange.length < layoutManager.numberOfGlyphs {
                    context.beginPage()

                    var yPosition: CGFloat = margin

                    if isFirstPage {
                        // Draw header on first page
                        yPosition = drawHeader(
                            context: context,
                            title: title,
                            timePeriod: timePeriod,
                            pageWidth: pageWidth,
                            margin: margin,
                            yPosition: yPosition
                        )
                        isFirstPage = false
                    }

                    // Calculate content area for this page
                    let availableHeight = pageHeight - yPosition - margin - 30 // 30 for footer

                    // Find the glyph range that fits in this page
                    let startGlyph = drawnGlyphRange.location + drawnGlyphRange.length
                    let contentOrigin = CGPoint(x: margin, y: yPosition)

                    // Create a temporary container for this page
                    let pageContainer = NSTextContainer(size: CGSize(width: contentWidth, height: availableHeight))
                    pageContainer.lineFragmentPadding = 0

                    let pageLayoutManager = NSLayoutManager()
                    let pageTextStorage = NSTextStorage(attributedString: attributedContent)
                    pageTextStorage.addLayoutManager(pageLayoutManager)
                    pageLayoutManager.addTextContainer(pageContainer)

                    // Get the range that fits
                    let rangeToShow = pageLayoutManager.glyphRange(for: pageContainer)

                    if rangeToShow.length == 0 && startGlyph > 0 {
                        break
                    }

                    // Adjust for what we've already drawn
                    let adjustedStart = min(startGlyph, layoutManager.numberOfGlyphs - 1)
                    let remainingGlyphs = layoutManager.numberOfGlyphs - adjustedStart

                    // Draw the text for this page
                    UIGraphicsPushContext(context.cgContext)

                    // Translate context to content origin
                    context.cgContext.saveGState()
                    context.cgContext.translateBy(x: contentOrigin.x, y: contentOrigin.y)

                    // Calculate what fits on this page
                    var lineY: CGFloat = 0
                    var lastGlyphIndex = adjustedStart

                    // Draw line by line until we run out of space
                    var lineIndex = 0
                    let totalLines = layoutManager.numberOfGlyphs > 0 ? Int(totalContentHeight / 15) : 0

                    // Simple approach: draw text that fits
                    let remainingText = attributedContent.attributedSubstring(
                        from: NSRange(location: adjustedStart, length: min(remainingGlyphs, attributedContent.length - adjustedStart))
                    )

                    let pageBoundingRect = CGRect(x: 0, y: 0, width: contentWidth, height: availableHeight)
                    remainingText.draw(with: pageBoundingRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)

                    context.cgContext.restoreGState()
                    UIGraphicsPopContext()

                    // Calculate how much we drew (estimate based on available height)
                    let drawnRect = remainingText.boundingRect(
                        with: CGSize(width: contentWidth, height: availableHeight),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        context: nil
                    )

                    let charactersFit = Int((availableHeight / totalContentHeight) * CGFloat(attributedContent.length))
                    drawnGlyphRange = NSRange(
                        location: adjustedStart,
                        length: min(charactersFit, attributedContent.length - adjustedStart)
                    )

                    // Draw footer
                    drawFooter(
                        context: context,
                        pageNumber: pageNumber,
                        pageWidth: pageWidth,
                        pageHeight: pageHeight,
                        margin: margin
                    )

                    pageNumber += 1

                    // Safety check to prevent infinite loops
                    if drawnGlyphRange.length == 0 || pageNumber > 50 {
                        break
                    }
                }
            }

            return data
        }

        private func drawHeader(
            context: UIGraphicsPDFRendererContext,
            title: String,
            timePeriod: String,
            pageWidth: CGFloat,
            margin: CGFloat,
            yPosition: CGFloat
        ) -> CGFloat {
            var y = yPosition

            // Title
            let titleFont = UIFont.boldSystemFont(ofSize: 18)
            let titleAttr: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: UIColor.black
            ]

            let fullTitle = "Trio \(title)"
            let titleSize = fullTitle.size(withAttributes: titleAttr)
            let titleRect = CGRect(
                x: (pageWidth - titleSize.width) / 2,
                y: y,
                width: titleSize.width,
                height: titleSize.height
            )
            fullTitle.draw(in: titleRect, withAttributes: titleAttr)
            y += titleSize.height + 8

            // Subtitle with date and time period
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .long
            dateFormatter.timeStyle = .short
            let subtitle = "Generated: \(dateFormatter.string(from: Date())) | Period: \(timePeriod)"
            let subtitleFont = UIFont.systemFont(ofSize: 10)
            let subtitleAttr: [NSAttributedString.Key: Any] = [
                .font: subtitleFont,
                .foregroundColor: UIColor.gray
            ]
            let subtitleSize = subtitle.size(withAttributes: subtitleAttr)
            let subtitleRect = CGRect(
                x: (pageWidth - subtitleSize.width) / 2,
                y: y,
                width: subtitleSize.width,
                height: subtitleSize.height
            )
            subtitle.draw(in: subtitleRect, withAttributes: subtitleAttr)
            y += subtitleSize.height + 15

            // Separator line
            let linePath = UIBezierPath()
            linePath.move(to: CGPoint(x: margin, y: y))
            linePath.addLine(to: CGPoint(x: pageWidth - margin, y: y))
            UIColor.lightGray.setStroke()
            linePath.lineWidth = 0.5
            linePath.stroke()
            y += 15

            return y
        }

        private func drawFooter(
            context: UIGraphicsPDFRendererContext,
            pageNumber: Int,
            pageWidth: CGFloat,
            pageHeight: CGFloat,
            margin: CGFloat
        ) {
            let footerFont = UIFont.systemFont(ofSize: 9)
            let footerAttr: [NSAttributedString.Key: Any] = [
                .font: footerFont,
                .foregroundColor: UIColor.gray
            ]

            // Page number
            let pageText = "Page \(pageNumber)"
            let pageSize = pageText.size(withAttributes: footerAttr)
            let pageRect = CGRect(
                x: (pageWidth - pageSize.width) / 2,
                y: pageHeight - margin + 10,
                width: pageSize.width,
                height: pageSize.height
            )
            pageText.draw(in: pageRect, withAttributes: footerAttr)

            // Disclaimer on first page footer
            if pageNumber == 1 {
                let disclaimer = "This report is for informational purposes. Consult your healthcare provider before making changes."
                let disclaimerSize = disclaimer.size(withAttributes: footerAttr)
                let disclaimerRect = CGRect(
                    x: (pageWidth - disclaimerSize.width) / 2,
                    y: pageHeight - margin + 22,
                    width: disclaimerSize.width,
                    height: disclaimerSize.height
                )
                disclaimer.draw(in: disclaimerRect, withAttributes: footerAttr)
            }
        }
    }
}
