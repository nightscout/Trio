import Combine
import Foundation
import LoopKit
import SwiftUI

protocol TrioModalAlertResponder: AnyObject {
    func handleAcknowledgement(identifier: LoopKit.Alert.Identifier)
    /// Snooze the alert (and any siblings of its type). Glucose alarms route
    /// to per-type suppression — snoozing a "low" silences all low alarms
    /// for `duration` but leaves urgent-low / high / forecasted-low firing
    /// normally. Pump / device alerts fall back to the global muter.
    func requestSnooze(identifier: LoopKit.Alert.Identifier, duration: TimeInterval)
    /// Returns true if the alert is still tracked by the manager. Used by
    /// `.delayed` timers to skip stale fires after the app resumes from
    /// suspension — the timer fires immediately on resume, and without this
    /// gate a banner would appear for an already-retracted alert.
    func isAlertActive(identifier: LoopKit.Alert.Identifier) -> Bool
    /// True if a global snooze is active. Non-critical `.delayed`/`.repeating`
    /// banners check this at fire time so a previously-scheduled banner
    /// (e.g. Not-Looping at +20m) stays silent during the snooze window.
    func isSnoozeActive(at date: Date) -> Bool
}

final class TrioModalAlertScheduler: ObservableObject {
    weak var responder: TrioModalAlertResponder?

    @Published private(set) var active: [LoopKit.Alert] = []
    private var pending: [LoopKit.Alert.Identifier: Timer] = [:]

    func schedule(_ alert: LoopKit.Alert) {
        DispatchQueue.main.async { [weak self] in self?.scheduleOnMain(alert) }
    }

    func unschedule(identifier: LoopKit.Alert.Identifier) {
        DispatchQueue.main.async { [weak self] in self?.unscheduleOnMain(identifier: identifier) }
    }

    func acknowledge(identifier: LoopKit.Alert.Identifier) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.acknowledge(identifier: identifier) }
            return
        }
        responder?.handleAcknowledgement(identifier: identifier)
        remove(identifier: identifier)
    }

    /// Drops every active non-critical banner. Called from `applySnooze` so
    /// banners visible at the moment a global snooze starts disappear too —
    /// otherwise they'd outlive the alarm they advertised.
    func clearNonCriticalBanners() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.clearNonCriticalBanners() }
            return
        }
        active.removeAll { $0.interruptionLevel != .critical }
    }

    func snooze(identifier: LoopKit.Alert.Identifier, duration: TimeInterval) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.snooze(identifier: identifier, duration: duration)
            }
            return
        }
        responder?.requestSnooze(identifier: identifier, duration: duration)
        // Drop the in-app banner too — the global snooze mutes the queue,
        // and leaving this specific banner hanging would be noise.
        remove(identifier: identifier)
    }

    /// "Snooze all" entry point from the expanded stack header. Each alert
    /// goes through its own routing — glucose per-type, device per-category,
    /// everything else global — so a mixed stack snoozes correctly bucket by
    /// bucket.
    func snoozeAll(duration: TimeInterval) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.snoozeAll(duration: duration) }
            return
        }
        let identifiers = active.map(\.identifier)
        for identifier in identifiers {
            responder?.requestSnooze(identifier: identifier, duration: duration)
        }
        active.removeAll()
    }

    private func scheduleOnMain(_ alert: LoopKit.Alert) {
        guard alert.foregroundContent != nil else { return }
        switch alert.trigger {
        case .immediate:
            insert(alert)
        case let .delayed(interval):
            scheduleTimer(alert: alert, interval: interval, repeats: false)
        case let .repeating(interval):
            scheduleTimer(alert: alert, interval: interval, repeats: true)
        }
    }

    private func unscheduleOnMain(identifier: LoopKit.Alert.Identifier) {
        pending.removeValue(forKey: identifier)?.invalidate()
        remove(identifier: identifier)
    }

    /// Outcome of a `.delayed`/`.repeating` timer fire, factored out of the
    /// timer closure so the snooze-pierce gate is unit-testable as a pure
    /// function. See `shouldInsertOnFire`.
    enum FireDecision: Equatable {
        case insert
        case suppressKeepPending
        case dropStale
    }

    /// Pure decision for what a timer fire should do, given the alert's
    /// interruption level and the manager's current active/snooze state.
    /// - `dropStale`: alert no longer tracked — skip and drop pending.
    /// - `suppressKeepPending`: non-critical banner muted by global snooze.
    /// - `insert`: present the banner.
    static func shouldInsertOnFire(
        interruptionLevel: LoopKit.Alert.InterruptionLevel,
        isAlertActive: Bool,
        isSnoozeActive: Bool
    ) -> FireDecision {
        guard isAlertActive else { return .dropStale }
        if interruptionLevel != .critical, isSnoozeActive { return .suppressKeepPending }
        return .insert
    }

    private func scheduleTimer(alert: LoopKit.Alert, interval: TimeInterval, repeats: Bool) {
        if pending[alert.identifier] != nil { return }
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: repeats) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                // Skip stale fires (e.g. iOS suspended the app for longer
                // than `interval`; on resume the timer fires immediately
                // even if the underlying alert was already retracted).
                let isAlertActive = self.responder?.isAlertActive(identifier: alert.identifier) ?? true
                // Honor active global snooze for non-critical banners.
                let isSnoozeActive = self.responder?.isSnoozeActive(at: Date()) == true
                switch Self.shouldInsertOnFire(
                    interruptionLevel: alert.interruptionLevel,
                    isAlertActive: isAlertActive,
                    isSnoozeActive: isSnoozeActive
                ) {
                case .dropStale:
                    self.pending.removeValue(forKey: alert.identifier)
                case .suppressKeepPending:
                    if !repeats {
                        self.pending.removeValue(forKey: alert.identifier)
                    }
                case .insert:
                    self.insert(alert)
                    if !repeats {
                        self.pending.removeValue(forKey: alert.identifier)
                    }
                }
            }
        }
        pending[alert.identifier] = timer
    }

    private func insert(_ alert: LoopKit.Alert) {
        guard !active.contains(where: { $0.identifier == alert.identifier }) else { return }
        active.append(alert)
        sortByPriority()
    }

    private func remove(identifier: LoopKit.Alert.Identifier) {
        active.removeAll { $0.identifier == identifier }
    }

    private func sortByPriority() {
        active.sort { Self.rank(of: $0.interruptionLevel) < Self.rank(of: $1.interruptionLevel) }
    }

    /// Lower rank = higher severity. Matches `DeviceAlertsStore.severityRank`
    /// so the sort convention is consistent across the alert pipeline.
    private static func rank(of level: LoopKit.Alert.InterruptionLevel) -> Int {
        switch level {
        case .critical: return 0
        case .timeSensitive: return 1
        case .active: return 2
        }
    }
}

struct TrioAlertBanner: View {
    let alert: LoopKit.Alert
    /// Single-tap action — `nil` means tap behaves like swipe-up (fires the
    /// 20-min snooze). The collapsed stack overrides this with "expand",
    /// since tapping a stacked card should reveal the rest of the deck
    /// before letting the user dismiss anything individually.
    var onTap: (() -> Void)? = nil
    /// Snooze path — fires from swipe-up + long-press menu + (when `onTap`
    /// is nil) tap.
    let onSnooze: (TimeInterval) -> Void

    @State private var presentedAt = Date()
    @State private var dragOffset: CGSize = .zero

    private static let quickSnooze: TimeInterval = 15 * 60

    /// Critical alerts and urgent-low glucose alarms are limited to the
    /// 20-minute quick snooze — the safety floor. Other alerts get the full
    /// 20m / 1h / 3h / 6h menu.
    private var isQuickSnoozeOnly: Bool {
        if alert.interruptionLevel == .critical { return true }
        if GlucoseAlertType(slug: alert.identifier.alertIdentifier) == .urgentLow { return true }
        return false
    }

    private var content: LoopKit.Alert.Content? { alert.foregroundContent }

    private var symbolName: String {
        switch alert.interruptionLevel {
        case .critical: return "exclamationmark.octagon.fill"
        case .timeSensitive: return "exclamationmark.triangle.fill"
        case .active: return "info.circle.fill"
        }
    }

    private var accent: Color {
        switch alert.interruptionLevel {
        case .critical: return .red
        case .timeSensitive: return .orange
        case .active: return .blue
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    if let title = content?.title, !title.isEmpty {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                    }
                    Spacer(minLength: 8)
                    TimelineView(.periodic(from: Date(), by: 5)) { context in
                        Text(relativeTimestamp(now: context.date))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if let body = content?.body, !body.isEmpty {
                    Text(body)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Menu {
                ForEach(snoozeOptions, id: \.self) { action in
                    Button {
                        onSnooze(action.duration)
                    } label: {
                        Label(action.localizedTitle, systemImage: "moon.zzz")
                    }
                }
            } label: {
                Image(systemName: "moon.zzz.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("Snooze"))
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .offset(y: min(0, dragOffset.height))
        .opacity(1 - min(abs(dragOffset.height) / CGFloat(200), 0.4))
        .gesture(
            // Swipe-up — iOS-banner gesture; tracks the drag visually then
            // commits a 20-minute snooze past −50pt. Springs back otherwise.
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    guard value.translation.height < 0 else { return }
                    dragOffset = value.translation
                }
                .onEnded { value in
                    if value.translation.height < -50 {
                        onSnooze(Self.quickSnooze)
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = .zero
                        }
                    }
                }
        )
        .onTapGesture {
            if let onTap { onTap() } else { onSnooze(Self.quickSnooze) }
        }
        .contextMenu {
            if isQuickSnoozeOnly {
                // Critical + urgent-low: a single labeled action; no header,
                // no other options.
                Button {
                    onSnooze(Self.quickSnooze)
                } label: {
                    Label(String(localized: "Snooze (15 min)"), systemImage: "moon.zzz")
                }
            } else {
                Section(String(localized: "Snooze")) {
                    ForEach(snoozeOptions, id: \.self) { action in
                        Button {
                            onSnooze(action.duration)
                        } label: {
                            Label(action.localizedTitle, systemImage: "moon.zzz")
                        }
                    }
                }
            }
        }
    }

    private var snoozeOptions: [NotificationResponseAction] {
        isQuickSnoozeOnly ? [.snooze15] : NotificationResponseAction.allCases
    }

    private func relativeTimestamp(now: Date) -> String {
        let elapsed = now.timeIntervalSince(presentedAt)
        if elapsed < 5 {
            return String(localized: "now")
        } else if elapsed < 60 {
            return String(format: String(localized: "%ds ago"), Int(elapsed))
        } else if elapsed < 3600 {
            return String(format: String(localized: "%dm ago"), Int(elapsed / 60))
        } else {
            return String(format: String(localized: "%dh ago"), Int(elapsed / 3600))
        }
    }
}

struct TrioAlertModifier: ViewModifier {
    @ObservedObject var scheduler: TrioModalAlertScheduler
    @State private var isExpanded = false

    private static let maxStackedVisible = 3

    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content
            if !scheduler.active.isEmpty {
                bannerStack
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .zIndex(1000)
            }
        }
        .onChange(of: scheduler.active.count) { _, newCount in
            if newCount <= 1 { isExpanded = false }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: scheduler.active.map(\.identifier.value))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isExpanded)
    }

    @ViewBuilder private var bannerStack: some View {
        if isExpanded || scheduler.active.count <= 1 {
            VStack(spacing: 8) {
                if scheduler.active.count > 1 {
                    snoozeAllHeader
                }
                ForEach(scheduler.active, id: \.identifier) { alert in
                    TrioAlertBanner(
                        alert: alert,
                        onSnooze: { duration in
                            scheduler.snooze(identifier: alert.identifier, duration: duration)
                        }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        } else {
            collapsedStack
        }
    }

    /// iOS-style "clear all" affordance at the top of the expanded stack.
    /// Runs every active alert through its own snooze routing — glucose
    /// per-type, device per-category, etc.
    private var snoozeAllHeader: some View {
        HStack {
            Spacer()
            Button {
                scheduler.snoozeAll(duration: 15 * 60)
            } label: {
                HStack(spacing: 4) {
                    Text(String(localized: "Snooze all (15 min)"))
                        .font(.footnote.weight(.semibold))
                    Image(systemName: "moon.zzz.fill")
                        .font(.footnote)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var collapsedStack: some View {
        let visible = scheduler.active.prefix(Self.maxStackedVisible)
        return ZStack(alignment: .top) {
            ForEach(Array(visible.enumerated().reversed()), id: \.element.identifier) { index, alert in
                TrioAlertBanner(
                    alert: alert,
                    onTap: {
                        // Tap on the collapsed deck expands it; individual
                        // banners then own their own tap-to-snooze.
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            isExpanded = true
                        }
                    },
                    onSnooze: { duration in
                        scheduler.snooze(identifier: alert.identifier, duration: duration)
                    }
                )
                .scaleEffect(1 - CGFloat(index) * 0.04, anchor: .top)
                .offset(y: CGFloat(index) * 14)
                .opacity(1 - Double(index) * 0.25)
                .allowsHitTesting(index == 0)
                .zIndex(Double(Self.maxStackedVisible - index))
            }
        }
    }
}

extension View {
    func trioAlerts(_ scheduler: TrioModalAlertScheduler) -> some View {
        modifier(TrioAlertModifier(scheduler: scheduler))
    }
}

#if DEBUG
    extension TrioModalAlertScheduler {
        /// Test-only seam: seeds the published `active` queue so tests can exercise
        /// `clearNonCriticalBanners()` without driving the private `insert` path.
        func seedForTesting(_ alerts: [LoopKit.Alert]) { active = alerts }
    }
#endif
