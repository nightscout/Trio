import SwiftUI

@Observable final class SettingsSearchHighlight {
    var highlightedSetting: String?
}

/// Wraps a Screen value with the scroll-target label for search-result navigation.
struct SearchResultTarget: Hashable {
    let screen: Screen
    let scrollLabel: String
}

private struct SettingsHighlightScrollModifier: ViewModifier {
    @Environment(SettingsSearchHighlight.self) private var searchHighlight

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .onAppear {
                    scrollToHighlight(proxy: proxy)
                }
                .onChange(of: searchHighlight.highlightedSetting) { _, newValue in
                    if newValue != nil {
                        scrollToHighlight(proxy: proxy)
                    }
                }
        }
    }

    private func scrollToHighlight(proxy: ScrollViewProxy) {
        guard let target = searchHighlight.highlightedSetting else { return }
        DispatchQueue.main.asyncAfter(deadline: .now().advanced(by: .milliseconds(500))) {
            withAnimation { proxy.scrollTo(target, anchor: .center) }
        }
    }
}

private struct SettingsSearchHighlightAnimationModifier: ViewModifier {
    let label: String
    @Environment(SettingsSearchHighlight.self) private var searchHighlight
    @State private var highlightOpacity: Double = 0.0

    func body(content: Content) -> some View {
        content
            .listRowBackground(
                Color.chart.overlay(Color.accentColor.opacity(highlightOpacity))
                    .animation(.easeOut(duration: 1.2), value: highlightOpacity)
            )
            .onAppear {
                guard searchHighlight.highlightedSetting == label else { return }
                startHighlightAnimation()
            }
            .onChange(of: searchHighlight.highlightedSetting) { _, newValue in
                guard newValue == label else { return }
                startHighlightAnimation()
            }
    }

    private func startHighlightAnimation() {
        searchHighlight.highlightedSetting = nil
        highlightOpacity = 0.6
        DispatchQueue.main.asyncAfter(deadline: .now().advanced(by: .milliseconds(1000))) {
            highlightOpacity = 0.0
        }
    }
}

extension View {
    /// Enables scroll-to-highlight on a settings screen. Add once per destination view.
    func settingsHighlightScroll() -> some View {
        modifier(SettingsHighlightScrollModifier())
    }

    /// Marks a section as a scroll-to and highlight target for settings search.
    /// Combines `.id(label)` with a highlight flash animation in a single call.
    func settingsSearchTarget(label: String) -> some View {
        id(label)
            .modifier(SettingsSearchHighlightAnimationModifier(label: label))
    }
}
