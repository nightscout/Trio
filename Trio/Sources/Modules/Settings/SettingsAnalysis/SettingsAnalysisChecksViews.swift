import SwiftUI

/// "Start Here", flagged checks and passed checks for the results screen.
struct SettingsChecksSections: View {
    let report: SettingsAnalysis.Report

    var body: some View {
        if let error = report.catalogError {
            Section {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } header: {
                Text("Settings Checks")
            }
            .listRowBackground(Color.chart)
        } else if let checks = report.checks {
            if let first = checks.startHere {
                Section {
                    NavigationLink(destination: SettingsCheckDetailView(result: first, catalog: report.catalog)) {
                        SettingsCheckRow(result: first, showsFinding: true)
                    }
                } header: {
                    Label("Start Here", systemImage: "flag")
                } footer: {
                    Text(
                        "Change one setting at a time and wait a few days before the next change. Settings that affect everything else come first."
                    )
                }
                .listRowBackground(Color.chart)
            }

            Section {
                if checks.flagged.isEmpty {
                    Label("No settings stood out.", systemImage: "checkmark.seal")
                        .foregroundStyle(.green)
                }
                ForEach(checks.flagged.dropFirst()) { result in
                    NavigationLink(destination: SettingsCheckDetailView(result: result, catalog: report.catalog)) {
                        SettingsCheckRow(result: result, showsFinding: true)
                    }
                }
                if !checks.passed.isEmpty {
                    DisclosureGroup {
                        ForEach(checks.passed) { result in
                            NavigationLink(destination: SettingsCheckDetailView(result: result, catalog: report.catalog)) {
                                SettingsCheckRow(result: result, showsFinding: false)
                            }
                        }
                    } label: {
                        Text("Passed (\(checks.passed.count))")
                    }
                }
            } header: {
                Text("Settings Checks")
            } footer: {
                Text("Based on your current settings. Rule catalog \(checks.catalogVersion).")
            }
            .listRowBackground(Color.chart)
        }
    }
}

struct SettingsCheckRow: View {
    let result: SettingsAnalysis.CheckResult
    let showsFinding: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: result.isFlagged ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(result.isFlagged ? .orange : .green)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(result.rule.title)
                    Spacer()
                    RuleIDChip(id: result.rule.id)
                }
                if showsFinding {
                    Text(result.rule.finding)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let observed = result.observed {
                    Text(observed)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct RuleIDChip: View {
    let id: String

    var body: some View {
        Text(verbatim: id)
            .font(.caption2.monospaced().weight(.semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .foregroundStyle(.secondary)
            .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            .accessibilityLabel(Text("Rule \(id)"))
    }
}

struct SettingsCheckDetailView: View {
    let result: SettingsAnalysis.CheckResult
    let catalog: SettingsAnalysis.Catalog?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    private var rule: SettingsAnalysis.Rule { result.rule }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(rule.title).font(.headline)
                        Spacer()
                        RuleIDChip(id: rule.id)
                    }
                    Text(rule.finding)
                        .font(.subheadline)
                    if let observed = result.observed {
                        LabeledContent("Current", value: observed)
                            .font(.subheadline)
                    }
                    if case let .notApplicable(reason) = result.outcome {
                        Text(reason)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(Color.chart)

            if result.isFlagged {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(rule.setting.uppercased())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.purple)
                        Text(rule.advice)
                        Text(rule.rationale)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("What This Usually Means")
                }
                .listRowBackground(Color.chart)
            }

            Section {
                LabeledContent("Direction", value: rule.direction.displayName)
                LabeledContent("Readiness", value: rule.readiness.confidence.displayName)
                LabeledContent("Evidence", value: String(localized: "\(rule.evidenceCount) messages"))
                if let lastSeen = rule.lastSeen {
                    LabeledContent("Last Confirmed", value: lastSeen)
                }
            } header: {
                Text("About This Rule")
            } footer: {
                if let catalog {
                    Text(catalog.source)
                }
            }
            .listRowBackground(Color.chart)

            let guards = rule.guards.compactMap { catalog?.guard($0) }
            if !guards.isEmpty {
                Section {
                    ForEach(guards) { item in
                        GuardRow(item: item)
                    }
                } header: {
                    Text("Related Guards")
                }
                .listRowBackground(Color.chart)
            }
        }
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle(rule.id)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct GuardRow: View {
    let item: SettingsAnalysis.Guard

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RuleIDChip(id: item.id)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.text)
                    .font(.subheadline)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(item.phase == 1 ? .green : .secondary)
            }
        }
    }

    private var statusText: String {
        switch item.phase {
        case 0: return String(localized: "Applied when curating the catalog")
        case 1: return String(localized: "Enforced")
        default: return String(localized: "Planned (Phase \(item.phase))")
        }
    }
}

/// Lists all guards and the catalog version.
struct SettingsAnalysisGuardsInfoView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    @State private var catalog: SettingsAnalysis.Catalog?
    @State private var error: String?

    var body: some View {
        List {
            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                .listRowBackground(Color.chart)
            }
            if let catalog {
                Section {
                    ForEach(catalog.guards) { item in
                        GuardRow(item: item)
                    }
                } header: {
                    Text("Guards")
                } footer: {
                    Text("Guards decide whether a rule may give advice at all. They apply before any rule fires.")
                }
                .listRowBackground(Color.chart)

                Section {
                    LabeledContent("Version", value: catalog.version)
                    LabeledContent("Rules", value: "\(catalog.rules.filter { $0.status == .current }.count)")
                    Text(catalog.source)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Rule Catalog")
                }
                .listRowBackground(Color.chart)
            }
        }
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle("How Advice Is Checked")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            do {
                catalog = try SettingsAnalysis.Catalog.loadBundled()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

extension SettingsAnalysis.CheckResult {
    var observed: String? {
        switch outcome {
        case let .flagged(observed),
             let .passed(observed): return observed
        case .notApplicable: return nil
        }
    }
}
