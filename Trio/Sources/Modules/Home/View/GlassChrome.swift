import SwiftUI

/// Shared chrome for the Home panels: real Liquid Glass on iOS 26,
/// material approximation below.
enum GlassChrome {
    /// system-glass panel rounding (not the design patch's 17pt)
    static let panelCornerRadius: CGFloat = 26

    static var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
    }
}

/// Glass panel background with optional tint; pre-26 falls back to
/// ultraThinMaterial + tint fill + stroke, matching the compat-mode look.
struct GlassPanelBackground: ViewModifier {
    var tint: Color?
    var tintOpacity: Double = 0.12
    var strokeOpacity: Double = 0.35
    var strokeWidth: CGFloat = 1

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    tint.map { Glass.regular.tint($0.opacity(tintOpacity)) } ?? .regular,
                    in: .rect(cornerRadius: GlassChrome.panelCornerRadius, style: .continuous)
                )
                // faint rim keeps tinted panels legible on busy backgrounds
                .overlay(GlassChrome.panelShape.strokeBorder(
                    (tint ?? Color.primary).opacity(strokeOpacity * 0.6),
                    lineWidth: strokeWidth
                ))
        } else {
            content
                .background(
                    GlassChrome.panelShape
                        .fill(.ultraThinMaterial)
                        .overlay(GlassChrome.panelShape.fill((tint ?? .clear).opacity(tintOpacity)))
                        .overlay(GlassChrome.panelShape.strokeBorder(
                            (tint ?? Color.primary).opacity(strokeOpacity),
                            lineWidth: strokeWidth
                        ))
                        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.10), radius: 3, y: 1)
                )
        }
    }
}

extension View {
    func glassPanel(
        tint: Color? = nil,
        tintOpacity: Double = 0.12,
        strokeOpacity: Double = 0.35,
        strokeWidth: CGFloat = 1
    ) -> some View {
        modifier(GlassPanelBackground(
            tint: tint,
            tintOpacity: tintOpacity,
            strokeOpacity: strokeOpacity,
            strokeWidth: strokeWidth
        ))
    }
}
