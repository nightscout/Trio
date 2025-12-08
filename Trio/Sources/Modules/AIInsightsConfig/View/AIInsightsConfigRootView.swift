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
                    Text("Get AI-powered insights about your glucose data using Claude.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .listRowBackground(Color.chart)

                Section(
                    header: Text("Analysis Tools"),
                    content: {
                        NavigationLink(destination: QuickAnalysisView()) {
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

                        NavigationLink(destination: AskClaudeView()) {
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

                        NavigationLink(destination: WeeklyReportView()) {
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
                    NavigationLink(destination: APIKeySettingsView()) {
                        HStack {
                            Image(systemName: "key.fill")
                                .foregroundColor(.orange)
                            Text("API Key Settings")
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

    // MARK: - Placeholder Views

    struct QuickAnalysisView: View {
        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            VStack(spacing: 20) {
                Spacer()

                Image(systemName: "bolt.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.yellow)

                Text("Quick Analysis")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Coming Soon")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Text("One-tap analysis of your last 7 days of data. Get instant insights about patterns, concerns, and actionable suggestions.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                Spacer()
            }
            .padding()
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Quick Analysis")
        }
    }

    struct AskClaudeView: View {
        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            VStack(spacing: 20) {
                Spacer()

                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)

                Text("Ask Claude")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Coming Soon")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Text("Have a conversation about your glucose data. Ask questions like \"Why am I high in the morning?\" or \"Are my carb ratios working?\"")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                Spacer()
            }
            .padding()
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Ask Claude")
        }
    }

    struct WeeklyReportView: View {
        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            VStack(spacing: 20) {
                Spacer()

                Image(systemName: "doc.text.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)

                Text("Weekly Report")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Coming Soon")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Text("Generate a comprehensive report with statistics, pattern analysis, observations, and recommendations to share with your healthcare provider.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                Spacer()
            }
            .padding()
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Weekly Report")
        }
    }

    struct APIKeySettingsView: View {
        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            Form {
                Section(
                    header: Text("Claude API Key"),
                    footer: Text("Get your API key from console.anthropic.com")
                ) {
                    Text("API Key")
                    Text("Not configured")
                        .foregroundColor(.secondary)
                }
                .listRowBackground(Color.chart)

                Section(
                    footer: Text("API key configuration will be available in a future update.")
                ) {
                    Text("Coming Soon")
                        .foregroundColor(.secondary)
                }
                .listRowBackground(Color.chart)
            }
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("API Key Settings")
        }
    }
}
