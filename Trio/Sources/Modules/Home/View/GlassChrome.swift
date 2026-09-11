import SwiftUI

/// Shared chrome for the Home panels: real Liquid Glass on iOS 26,
/// material approximation below.
enum GlassChrome {
    /// system-glass panel rounding (not the design patch's 17pt)
    static let panelCornerRadius: CGFloat = 26

    static var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
    }

    /// Stand-in for glass/material when Reduce Transparency is on: no blur, so
    /// nothing behind the panel bleeds through.
    static let opaqueFill = Color(.secondarySystemGroupedBackground)
}

/// Glass panel background with optional tint; pre-26 falls back to
/// ultraThinMaterial + tint fill + stroke, matching the compat-mode look.
///
/// Accessibility: with Reduce Transparency or Increase Contrast enabled, both the
/// glass and material paths are dropped for an opaque, higher-contrast fill so
/// low-vision users get legible chrome instead of translucent panels.
struct GlassPanelBackground: ViewModifier {
    var tint: Color?
    var tintOpacity: Double = 0.12
    var strokeOpacity: Double = 0.35
    var strokeWidth: CGFloat = 1

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    /// True when the user has asked for reduced transparency or increased contrast.
    private var prefersOpaque: Bool {
        reduceTransparency || colorSchemeContrast == .increased
    }

    func body(content: Content) -> some View {
        // Reduce Transparency / Increase Contrast skip the glass and material paths entirely
        // for a fully opaque panel; the glass path in particular cannot be made opaque.
        if prefersOpaque {
            content.background(opaquePanel)
        } else if #available(iOS 26.0, *) {
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

    /// Opaque, higher-contrast panel used when transparency is reduced / contrast increased.
    private var opaquePanel: some View {
        GlassChrome.panelShape
            .fill(Color(.secondarySystemBackground))
            .overlay(GlassChrome.panelShape.fill((tint ?? .clear).opacity(min(tintOpacity * 1.5, 0.30))))
            .overlay(GlassChrome.panelShape.strokeBorder(
                (tint ?? Color.primary).opacity(max(strokeOpacity, 0.6)),
                lineWidth: strokeWidth + 0.5
            ))
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.10), radius: 3, y: 1)
    }
}

/// Material fill for small glass affordances (rate capsule, chart-info circle) that
/// becomes an opaque fill under Reduce Transparency / Increase Contrast.
struct GlassMaterialFill<S: InsettableShape>: ViewModifier {
    let shape: S

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    func body(content: Content) -> some View {
        if reduceTransparency || colorSchemeContrast == .increased {
            content.background(shape.fill(Color(.secondarySystemBackground)))
        } else {
            content.background(shape.fill(.ultraThinMaterial))
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

    /// Material fill for a small shape (capsule/circle) that turns opaque under
    /// Reduce Transparency / Increase Contrast.
    func glassMaterialFill(_ shape: some InsettableShape) -> some View {
        modifier(GlassMaterialFill(shape: shape))
    }
}
