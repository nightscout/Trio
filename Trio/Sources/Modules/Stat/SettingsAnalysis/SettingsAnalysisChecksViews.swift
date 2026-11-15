import SwiftUI

/// "Start Here", flagged checks and passed checks for the results.
struct SettingsChecksCards: View {
    let report: SettingsAnalysis.Report

    var body: some View {
        if let error = report.catalogError {
            SettingsAnalysisCard(Text("Settings Checks")) {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        } else if let checks = report.checks {
            if let first = checks.startHere {
                SettingsAnalysisCard(Text("\(Image(systemName: "flag")) Start Here")) {
                    link(for: first, showsFinding: true)
                } footer: {
                    Text(
                        "Change one setting at a time and wait a few days before the next change. Settings that affect everything else come first."
                    )
                }
            }

            SettingsAnalysisCard(Text("Settings Checks")) {
                if checks.flagged.isEmpty {
                    Label("No settings stood out.", systemImage: "checkmark.seal")
                        .foregroundStyle(.green)
                }
                ForEach(Array(checks.flagged.dropFirst().enumerated()), id: \.element.id) { index, result in
                    if index > 0 { Divider() }
                    link(for: result, showsFinding: true)
                }
                if !checks.passed.isEmpty {
                    if checks.flagged.count > 1 { Divider() }
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(checks.passed) { result in
                                Divider()
                                link(for: result, showsFinding: false)
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        Text("Passed (\(checks.passed.count))")
                    }
                }
            } footer: {
                Text("Based on your current settings. Rule catalog \(checks.catalogVersion).")
            }
        }
    }

    private func link(for result: SettingsAnalysis.CheckResult, showsFinding: Bool) -> some View {
        SettingsAnalysisLinkRow(destination: SettingsCheckDetailView(result: result, catalog: report.catalog)) {
            SettingsCheckRow(result: result, showsFinding: showsFinding)
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

extension SettingsAnalysis.CheckResult {
    var observed: String? {
        switch outcome {
        case let .flagged(observed),
             let .passed(observed): return observed
        case .notApplicable: return nil
        }
    }
}
