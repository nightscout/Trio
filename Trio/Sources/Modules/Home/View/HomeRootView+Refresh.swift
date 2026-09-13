import SwiftUI
import UIKit

/// Pull distance via layout frames — iOS 17 fallback only.
struct HomePullOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Streams the pull-down distance from the scroll geometry on iOS 18+.
struct HomePullOffsetReader: ViewModifier {
    let onChange: (CGFloat) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                -(geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { _, pull in
                onChange(pull)
            }
        } else {
            content
        }
    }
}

// MARK: - Pull-down-to-force-loop

extension Home.RootView {
    /// Pull hint while dragging; spinner while the loop runs.
    @ViewBuilder var pullToRefreshIndicator: some View {
        if isForcingLoop {
            HStack(spacing: 8) {
                ProgressView()
                Text("Forcing loop…")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(height: HomeLayout.refreshIndicatorHeight)
            .frame(maxWidth: .infinity)
            .transition(.opacity)
        } else if pullOffset > 4 {
            let progress = min(pullOffset / HomeLayout.refreshTriggerDistance, 1)
            HStack(spacing: 8) {
                Image(systemName: "arrow.down")
                    .rotationEffect(.degrees(progress * 180))
                Text("Pull down to force loop")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .opacity(progress)
            .frame(height: HomeLayout.refreshIndicatorHeight)
            .frame(maxWidth: .infinity)
        }
    }

    /// Arms once per pull at the threshold; re-arms after the pull settles.
    func handlePullChange(_ offset: CGFloat) {
        pullOffset = offset
        guard !isForcingLoop else { return }
        if offset >= HomeLayout.refreshTriggerDistance, !isRefreshArmed {
            isRefreshArmed = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            forceLoop()
        } else if offset <= 1, isRefreshArmed {
            isRefreshArmed = false
        }
    }

    /// Triggers the loop heartbeat and holds the indicator while it runs.
    private func forceLoop() {
        withAnimation(.easeInOut(duration: 0.2)) { isForcingLoop = true }
        state.runLoop()
        Task {
            let start = Date()
            while !state.isLooping, Date().timeIntervalSince(start) < 3 {
                try? await Task.sleep(for: .milliseconds(100))
            }
            while state.isLooping, Date().timeIntervalSince(start) < 30 {
                try? await Task.sleep(for: .milliseconds(200))
            }
            // Minimum visible duration.
            if Date().timeIntervalSince(start) < 1 {
                try? await Task.sleep(for: .seconds(1))
            }
            withAnimation(.easeInOut(duration: 0.25)) { isForcingLoop = false }
        }
    }
}
