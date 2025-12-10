import Combine
import CoreData
import PDFKit
import SwiftUI

extension AIInsightsConfig {
    enum Config {
        static let apiKeyKey = "AIInsightsConfig.claudeAPIKey"
        static let useNightscoutKey = "AIInsightsConfig.useNightscout"
        // Doctor Report Settings Keys
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
        private var nightscoutFetcher: NightscoutDataFetcher!

        // API Key
        @Published var apiKey = ""
        @Published var isAPIKeyConfigured = false
        @Published var isAPIKeyVisible = false

        // Nightscout Data Source
        @Published var useNightscout = true
        @Published var isNightscoutAvailable = false

        // Quick Analysis
        @Published var quickAnalysisResult = ""
        @Published var isAnalyzing = false
        @Published var analysisError: String?

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

        // Doctor Report Settings - Data to include
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
            // Initialize NightscoutDataFetcher with keychain
            nightscoutFetcher = NightscoutDataFetcher(keychain: keychain)

            // Load API key from keychain
            if let storedKey = keychain.getValue(String.self, forKey: Config.apiKeyKey) {
                apiKey = storedKey
                isAPIKeyConfigured = !storedKey.isEmpty
            }

            // Load Nightscout preference
            useNightscout = UserDefaults.standard.bool(forKey: Config.useNightscoutKey)
            if !UserDefaults.standard.dictionaryRepresentation().keys.contains(Config.useNightscoutKey) {
                // Default to true if not set
                useNightscout = true
            }

            // Check if Nightscout is available
            isNightscoutAvailable = nightscoutFetcher.isNightscoutConfigured

            // Get current units
            units = settingsManager.settings.units

            // Load Doctor Report Settings
            loadDoctorReportSettings()
        }

        private func loadDoctorReportSettings() {
            let defaults = UserDefaults.standard
            let keys = defaults.dictionaryRepresentation().keys

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

        func saveDoctorReportSettings() {
            let defaults = UserDefaults.standard
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

        func resetDoctorReportPrompt() {
            drCustomPrompt = AIInsightsConfig.defaultDoctorReportPrompt
            UserDefaults.standard.set(drCustomPrompt, forKey: Config.drCustomPromptKey)
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

        // MARK: - Nightscout Settings

        func toggleNightscout(_ enabled: Bool) {
            useNightscout = enabled
            UserDefaults.standard.set(enabled, forKey: Config.useNightscoutKey)
        }

        // MARK: - Data Export

        private func exportData() async throws -> HealthDataExporter.ExportedData {
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

            // If Nightscout is enabled and available, use it
            if useNightscout && isNightscoutAvailable {
                do {
                    let nsData = try await nightscoutFetcher.fetchComprehensiveData(days: 7)
                    return try await exporter.exportWithNightscout(
                        nightscoutData: nsData,
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
                } catch {
                    // Fall back to local data if Nightscout fails
                    print("Nightscout fetch failed, using local data: \(error)")
                }
            }

            return try await exporter.exportLast7Days(
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

        private func exportDataForDoctorVisit() async throws -> HealthDataExporter.ExportedData {
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

            // For Doctor Visit, try to get 90 days of data from Nightscout
            var nightscoutData: NightscoutDataFetcher.FetchedData?
            if useNightscout && isNightscoutAvailable {
                do {
                    nightscoutData = try await nightscoutFetcher.fetchComprehensiveData(days: 90)
                } catch {
                    print("Nightscout fetch for doctor visit failed: \(error)")
                }
            }

            return try await exporter.exportForDoctorVisit(
                units: settings.units.rawValue,
                targetLow: lowTarget,
                targetHigh: highTarget,
                maxIOB: preferences.maxIOB,
                maxBolus: pumpSettings.maxBolus,
                dia: pumpSettings.insulinActionCurve,
                carbRatioSchedule: carbRatioSchedule,
                isfSchedule: isfSchedule,
                basalSchedule: basalSchedule,
                targetSchedule: targetSchedule,
                nightscoutData: nightscoutData
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
                let data = try await exportData()
                let exporter = HealthDataExporter(context: coredataContext)
                let prompt = exporter.formatForPrompt(data, analysisType: .quick)

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

                // If this is the first message, include data context
                if chatMessages.count == 1 {
                    let data = try await exportData()
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
                let data = try await exportData()
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
                let data = try await exportDataForDoctorVisit()
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
                    customPrompt: drCustomPrompt
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
            Data Source: \(useNightscout && isNightscoutAvailable ? "Nightscout (up to 90 days)" : "Local App Data (7 days)")

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
