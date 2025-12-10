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

                // Generate PDF
                doctorReportPDFData = generatePDF(from: result, data: data)
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

        private func generatePDF(
            from report: String,
            data: HealthDataExporter.ExportedData
        ) -> Data? {
            let pageWidth: CGFloat = 612 // Letter size
            let pageHeight: CGFloat = 792
            let margin: CGFloat = 50

            let pdfMetaData = [
                kCGPDFContextCreator: "Trio AI Insights",
                kCGPDFContextAuthor: "Trio App",
                kCGPDFContextTitle: "Diabetes Management Report"
            ]

            let format = UIGraphicsPDFRendererFormat()
            format.documentInfo = pdfMetaData as [String: Any]

            let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
            let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

            let data = renderer.pdfData { context in
                context.beginPage()

                var yPosition: CGFloat = margin

                // Title
                let titleFont = UIFont.boldSystemFont(ofSize: 18)
                let titleAttr: [NSAttributedString.Key: Any] = [
                    .font: titleFont,
                    .foregroundColor: UIColor.black
                ]

                let title = "Trio Diabetes Management Report"
                let titleSize = title.size(withAttributes: titleAttr)
                let titleRect = CGRect(
                    x: (pageWidth - titleSize.width) / 2,
                    y: yPosition,
                    width: titleSize.width,
                    height: titleSize.height
                )
                title.draw(in: titleRect, withAttributes: titleAttr)
                yPosition += titleSize.height + 10

                // Date
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .long
                dateFormatter.timeStyle = .short
                let dateString = "Generated: \(dateFormatter.string(from: Date()))"
                let dateFont = UIFont.systemFont(ofSize: 10)
                let dateAttr: [NSAttributedString.Key: Any] = [
                    .font: dateFont,
                    .foregroundColor: UIColor.gray
                ]
                let dateSize = dateString.size(withAttributes: dateAttr)
                let dateRect = CGRect(
                    x: (pageWidth - dateSize.width) / 2,
                    y: yPosition,
                    width: dateSize.width,
                    height: dateSize.height
                )
                dateString.draw(in: dateRect, withAttributes: dateAttr)
                yPosition += dateSize.height + 20

                // Separator line
                let linePath = UIBezierPath()
                linePath.move(to: CGPoint(x: margin, y: yPosition))
                linePath.addLine(to: CGPoint(x: pageWidth - margin, y: yPosition))
                UIColor.gray.setStroke()
                linePath.stroke()
                yPosition += 20

                // Body content
                let bodyFont = UIFont.systemFont(ofSize: 11)
                let bodyAttr: [NSAttributedString.Key: Any] = [
                    .font: bodyFont,
                    .foregroundColor: UIColor.black
                ]

                let textRect = CGRect(
                    x: margin,
                    y: yPosition,
                    width: pageWidth - 2 * margin,
                    height: pageHeight - yPosition - margin
                )

                // Clean up markdown for PDF
                let cleanReport = report
                    .replacingOccurrences(of: "**", with: "")
                    .replacingOccurrences(of: "###", with: "")
                    .replacingOccurrences(of: "##", with: "")
                    .replacingOccurrences(of: "#", with: "")

                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.lineBreakMode = .byWordWrapping
                paragraphStyle.lineSpacing = 4

                let attrString = NSAttributedString(
                    string: cleanReport,
                    attributes: [
                        .font: bodyFont,
                        .foregroundColor: UIColor.black,
                        .paragraphStyle: paragraphStyle
                    ]
                )

                attrString.draw(in: textRect)
            }

            return data
        }
    }
}
