import SwiftUI

struct GarminFirestoreStatusView: View {
    @State private var configStatus: CheckStatus = .unknown
    @State private var authStatus: CheckStatus = .unknown
    @State private var dataStatus: CheckStatus = .unknown
    @State private var isTesting = false
    @State private var latestSnapshot: GarminContextSnapshot?
    @State private var sensitivityResult: SmartSenseResult?
    @State private var errorMessage: String?

    enum CheckStatus {
        case unknown, checking, pass, fail

        var icon: String {
            switch self {
            case .unknown: return "circle.dashed"
            case .checking: return "arrow.trianglehead.2.clockwise"
            case .pass: return "checkmark.circle.fill"
            case .fail: return "xmark.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .unknown: return .secondary
            case .checking: return .orange
            case .pass: return .green
            case .fail: return .red
            }
        }
    }

    var body: some View {
        Form {
            Section(header: Text("Connection Status")) {
                statusRow(label: "Configuration", status: configStatus, detail: configDetail)
                statusRow(label: "Firebase Sign-In", status: authStatus, detail: authDetail)
                statusRow(label: "Firestore Data", status: dataStatus, detail: dataDetail)
            }

            Section {
                Button {
                    Task { await runConnectionTest() }
                } label: {
                    HStack {
                        Spacer()
                        if isTesting {
                            ProgressView()
                                .padding(.trailing, 8)
                            Text("Testing...")
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                            Text("Test Connection")
                        }
                        Spacer()
                    }
                }
                .disabled(isTesting)
            }

            if let error = errorMessage {
                Section(header: Text("Error Details")) {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let snapshot = latestSnapshot {
                Section(header: Text("Latest Garmin Data")) {
                    dataRow("Sleep Score", value: snapshot.sleepScoreValue.map { "\($0)/100" })
                    dataRow("Sleep Duration", value: snapshot.totalSleepMinutes.map { "\($0 / 60)h \($0 % 60)m" })
                    dataRow("Resting HR", value: snapshot.restingHeartRateInBeatsPerMinute.map { "\($0) bpm" })
                    dataRow("7-Day Avg RHR", value: snapshot.restingHR7DayAvg.map { "\($0) bpm" })
                    dataRow("RHR Delta", value: snapshot.restingHRDelta.map { "\($0 > 0 ? "+" : "")\($0) bpm" })
                    dataRow("HRV (last night)", value: snapshot.lastNightAvg.map { "\($0) ms" })
                    dataRow("HRV Weekly Avg", value: snapshot.hrvWeeklyAvg.map { "\($0) ms" })
                    dataRow("HRV Delta", value: snapshot.hrvDeltaPercent.map { String(format: "%+.1f%%", $0) })
                    dataRow("Body Battery", value: snapshot.currentBodyBattery.map { "\($0)/100" })
                    dataRow("Body Battery at Wake", value: snapshot.bodyBatteryAtWake.map { "\($0)/100" })
                    dataRow("Stress Level", value: snapshot.currentStressLevel.map { "\($0)/100" })
                    dataRow("Avg Stress", value: snapshot.averageStressLevel.map { "\($0)/100" })
                    dataRow("Active Calories", value: snapshot.activeKilocalories.map { "\($0) kcal" })
                    dataRow("Yesterday Calories", value: snapshot.yesterdayActiveKilocalories.map { "\($0) kcal" })
                    dataRow("Steps", value: snapshot.steps.map { "\($0)" })
                    dataRow("VO2 Max", value: snapshot.vo2Max.map { String(format: "%.1f", $0) })
                }
            }

            if let result = sensitivityResult {
                Section(header: Text("SmartSense Factor Breakdown")) {
                    ForEach(result.garminFactors, id: \.factor) { factor in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(factor.factor)
                                    .font(.subheadline)
                                Text(factor.value)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(String(format: "%+.1f%%", factor.weightedImpact * 100))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(factor.weightedImpact > 0 ? .red : factor.weightedImpact < 0 ? .green : .secondary)
                                Text("w: \(Int(factor.weight * 100))%")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Divider()

                    HStack {
                        Text("Garmin Composite")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(String(format: "%+.1f%%", result.garminComposite * 100))
                            .font(.subheadline.weight(.medium).monospacedDigit())
                    }

                    HStack {
                        Text("Blended Suggestion")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(String(format: "%+.1f%%", result.blendedSuggestion * 100))
                            .font(.subheadline.weight(.medium).monospacedDigit())
                    }

                    HStack {
                        Text("Final Ratio")
                            .font(.headline)
                        Spacer()
                        Text(String(format: "%.2f", result.finalRatio))
                            .font(.headline.monospacedDigit())
                    }
                }
            }

            Section(header: Text("Configuration")) {
                configInfoRow("Project ID", value: maskedValue(GarminFirebaseConstants.projectID))
                configInfoRow("User ID", value: maskedValue(GarminFirebaseConstants.firestoreUserID))
                configInfoRow("Auth Email", value: maskedValue(GarminFirebaseConstants.authEmail))
            }
        }
        .navigationTitle("Garmin Health Data")
        .navigationBarTitleDisplayMode(.automatic)
        .onAppear {
            checkInitialStatus()
        }
    }

    // MARK: - Status Row

    private func statusRow(label: String, status: CheckStatus, detail: String?) -> some View {
        HStack {
            Image(systemName: status.icon)
                .foregroundStyle(status.color)
                .frame(width: 24)
            Text(label)
            Spacer()
            if let detail = detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var configDetail: String? {
        configStatus == .pass ? "Secrets injected" : configStatus == .fail ? "Missing secrets" : nil
    }

    private var authDetail: String? {
        authStatus == .pass ? "Authenticated" : authStatus == .fail ? "Failed" : nil
    }

    private var dataDetail: String? {
        dataStatus == .pass ? "Data found" : dataStatus == .fail ? "No data" : nil
    }

    // MARK: - Data Display

    private func dataRow(_ label: String, value: String?) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(value ?? "—")
                .font(.subheadline)
                .foregroundStyle(value != nil ? .primary : .secondary)
        }
    }

    private func configInfoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Connection Test

    private func checkInitialStatus() {
        configStatus = GarminFirebaseConstants.isConfigured ? .pass : .fail
        authStatus = GarminFirebaseManager.isSignedIn ? .pass : .unknown
    }

    private func runConnectionTest() async {
        isTesting = true
        errorMessage = nil
        latestSnapshot = nil
        sensitivityResult = nil

        // Step 1: Config
        configStatus = .checking
        try? await Task.sleep(nanoseconds: 200_000_000)

        guard GarminFirebaseConstants.isConfigured else {
            configStatus = .fail
            authStatus = .fail
            dataStatus = .fail
            errorMessage = "Firebase secrets were not injected at build time. Add GARMIN_FIREBASE_* secrets to your GitHub repository."
            isTesting = false
            return
        }
        configStatus = .pass

        // Step 2: Auth
        authStatus = .checking
        await GarminFirebaseManager.configureAndSignIn()

        guard GarminFirebaseManager.isSignedIn else {
            authStatus = .fail
            dataStatus = .fail
            errorMessage = "Firebase sign-in failed. Check your GARMIN_FIREBASE_EMAIL and GARMIN_FIREBASE_PASSWORD secrets."
            isTesting = false
            return
        }
        authStatus = .pass

        // Step 3: Data
        dataStatus = .checking
        let service = GarminFirestoreService()
        let snapshot = await service.fetchContext()

        if let snapshot = snapshot {
            dataStatus = .pass
            latestSnapshot = snapshot
        } else {
            dataStatus = .fail
            errorMessage = "Signed in but no Garmin data found in Firestore. Check that your Garmin webhooks are populating data."
            isTesting = false
            return
        }

        isTesting = false
    }

    private func maskedValue(_ value: String) -> String {
        if value.hasPrefix("__") { return "Not configured" }
        if value.count <= 8 { return value }
        return String(value.prefix(4)) + "..." + String(value.suffix(4))
    }
}
