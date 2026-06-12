import Combine
import Foundation
import LoopKit
import SwiftUI

protocol TrioModalAlertResponder: AnyObject {
    func handleAcknowledgement(identifier: LoopKit.Alert.Identifier)
    /// Applies a global snooze for `duration` seconds — same path as the UN
    /// quick-action buttons + the Snooze module + Apple Watch action.
    func requestSnooze(duration: TimeInterval)
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
        responder?.requestSnooze(duration: duration)
        // Drop the in-app banner too — the global snooze mutes the queue,
        // and leaving this specific banner hanging would be noise.
        remove(identifier: identifier)
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

    private func scheduleTimer(alert: LoopKit.Alert, interval: TimeInterval, repeats: Bool) {
        if pending[alert.identifier] != nil { return }
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: repeats) { [weak self] _ in
            DispatchQueue.main.async {
                // Skip stale fires (e.g. iOS suspended the app for longer
                // than `interval`; on resume the timer fires immediately
                // even if the underlying alert was already retracted).
                guard let self, self.responder?.isAlertActive(identifier: alert.identifier) ?? true else {
                    self?.pending.removeValue(forKey: alert.identifier)
                    return
                }
                // Honor active global snooze for non-critical banners.
                if alert.interruptionLevel != .critical,
                   self.responder?.isSnoozeActive(at: Date()) == true
                {
                    if !repeats {
                        self.pending.removeValue(forKey: alert.identifier)
                    }
                    return
                }
                self.insert(alert)
                if !repeats {
                    self.pending.removeValue(forKey: alert.identifier)
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
        active.sort { Self.priority(of: $0.interruptionLevel) > Self.priority(of: $1.interruptionLevel) }
    }

    private static func priority(of level: LoopKit.Alert.InterruptionLevel) -> Int {
        switch level {
        case .critical: return 2
        case .timeSensitive: return 1
        case .active: return 0
        }
    }
}

struct TrioAlertBanner: View {
    let alert: LoopKit.Alert
    let onTap: () -> Void
    let onSwipeAway: () -> Void
    let onSnooze: (TimeInterval) -> Void

    @State private var presentedAt = Date()
    @State private var dragOffset: CGFloat = 0

    private var canSnooze: Bool { alert.interruptionLevel != .critical }

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

            if canSnooze {
                Menu {
                    ForEach(NotificationResponseAction.allCases, id: \.self) { action in
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
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .offset(x: dragOffset)
        .opacity(1 - min(abs(dragOffset) / 200, 0.6))
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    let dx = value.translation.width
                    dragOffset = abs(dx) > abs(value.translation.height) ? dx : 0
                }
                .onEnded { value in
                    let dx = value.translation.width
                    // Swipe right past threshold → dismiss / acknowledge.
                    // Swipe left past threshold → quick snooze (20m) when
                    // the alert isn't critical. Otherwise reset.
                    if dx > 80 {
                        onSwipeAway()
                    } else if dx < -80, canSnooze {
                        onSnooze(NotificationResponseAction.snooze20.duration)
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .onTapGesture { onTap() }
        .contextMenu {
            if canSnooze {
                Section(String(localized: "Snooze")) {
                    ForEach(NotificationResponseAction.allCases, id: \.self) { action in
                        Button {
                            onSnooze(action.duration)
                        } label: {
                            Label(action.localizedTitle, systemImage: "moon.zzz")
                        }
                    }
                }
            }
            Button {
                onTap()
            } label: {
                Label(String(localized: "Acknowledge"), systemImage: "checkmark")
            }
        }
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
                ForEach(scheduler.active, id: \.identifier) { alert in
                    TrioAlertBanner(
                        alert: alert,
                        onTap: { scheduler.acknowledge(identifier: alert.identifier) },
                        onSwipeAway: { scheduler.acknowledge(identifier: alert.identifier) },
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

    private var collapsedStack: some View {
        let visible = scheduler.active.prefix(Self.maxStackedVisible)
        return ZStack(alignment: .top) {
            ForEach(Array(visible.enumerated().reversed()), id: \.element.identifier) { index, alert in
                TrioAlertBanner(
                    alert: alert,
                    onTap: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            isExpanded = true
                        }
                    },
                    onSwipeAway: { scheduler.acknowledge(identifier: alert.identifier) },
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
