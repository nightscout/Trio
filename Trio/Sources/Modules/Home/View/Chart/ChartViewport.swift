import Foundation
import SwiftUI

/// The mapping between chart time and viewport x — the one every layer the shell draws over
/// the canvas shares.
///
/// Ported from the `dev` branch, where it replaced five hand-written copies of `x(for:)`. The
/// one form that cannot work is a *closure* over the shell's `scrollPosition`: it captures
/// that value at its final position and so ignores the interpolation an animated scroll
/// depends on — which is exactly why `ChartOverlayLayer` below passes a viewport instead.
///
/// `visibleStart` is a `var` because `ChartOverlayLayer` interpolates it; everything else about
/// a viewport is fixed for the frame it describes.
struct ChartViewport: Equatable {
    /// Leading edge of the visible window, and how much time it spans.
    var visibleStart: Date
    let visibleSeconds: TimeInterval
    let viewportWidth: CGFloat

    /// The live-pinch stretch and the centroid it is anchored under. A pinch previews the zoom
    /// by scaling the already-laid-out canvas, so between touch-down and commit the content on
    /// screen is stretched about that anchor; every layer outside the canvas has to apply the
    /// same transform to its coordinates or drift off the marks it belongs to.
    let pinchScale: CGFloat
    let pinchAnchorFraction: CGFloat?

    /// Viewport x of a date, including the live-pinch stretch.
    func x(for date: Date) -> CGFloat {
        let x = CGFloat(date.timeIntervalSince(visibleStart) / visibleSeconds) * viewportWidth
        guard let anchorFraction = pinchAnchorFraction, pinchScale != 1 else { return x }
        let anchorX = anchorFraction * viewportWidth
        return anchorX + (x - anchorX) * pinchScale
    }

    /// The inverse: the date currently under a viewport x.
    ///
    /// This is what cull ranges are measured with. Deriving them from `visibleSeconds` instead
    /// is wrong while a pinch is live: the stretch means a zoom-out has a *wider* span of time
    /// on screen than the committed window, and culling to the committed one leaves the newly
    /// exposed edges bare until the zoom commits.
    func date(atViewportX x: CGFloat) -> Date {
        var untransformed = x
        if let anchorFraction = pinchAnchorFraction, pinchScale != 1, pinchScale > 0 {
            let anchorX = anchorFraction * viewportWidth
            untransformed = anchorX + (x - anchorX) / pinchScale
        }
        return visibleStart.addingTimeInterval(
            TimeInterval(untransformed / max(viewportWidth, 1)) * visibleSeconds
        )
    }

    /// Chart time per point *as currently drawn* — so it follows the pinch, like the on-screen
    /// distances it converts.
    var secondsPerPoint: TimeInterval {
        let scale = pinchScale > 0 ? Double(pinchScale) : 1
        return visibleSeconds / Double(max(viewportWidth, 1)) / scale
    }

    /// What is on screen, plus room for a mark that has just left it.
    ///
    /// - Parameters:
    ///   - marginPoints: How far past each edge to reach, in points — a mark whose centre has
    ///     just gone by can still have pixels inside.
    ///   - minimumSlack: A floor on that reach, in chart time. `GlucoseDotsOverlay` needs one
    ///     reading's worth (300 s) so its smoothed curve enters from off-screen rather than
    ///     stopping short of the edge.
    func cullRange(marginPoints: CGFloat, minimumSlack: TimeInterval = 0) -> ClosedRange<Date> {
        let start = date(atViewportX: -marginPoints).addingTimeInterval(-minimumSlack)
        let end = date(atViewportX: viewportWidth + marginPoints).addingTimeInterval(minimumSlack)
        return start ... Swift.max(start, end)
    }

    /// The leading edge as a scalar SwiftUI can interpolate — see `ChartOverlayLayer`.
    var animatableTime: Double {
        get { visibleStart.timeIntervalSinceReferenceDate }
        set { visibleStart = Date(timeIntervalSinceReferenceDate: newValue) }
    }
}

/// Container for one shell overlay: it owns the animation and the frame, so the layer inside it
/// owns only its own drawing.
///
/// **The contract:** `content` is handed the viewport as a parameter, and every coordinate it
/// computes must come from *that* value. A `Date` handed to a view is not animatable at all, so
/// a layer positioned from the shell's `scrollPosition` — already at its destination when an
/// animated scroll begins — snaps there while the canvas glides under it. Interpolating
/// `animatableData` here re-runs this body each frame with an intermediate viewport, which is
/// what makes the markers travel with the chart. Reach past the parameter for the shell's own
/// state and that stops being true, which is the bug this shape exists to prevent.
struct ChartOverlayLayer<Content: View>: View, Animatable {
    var viewport: ChartViewport
    /// Height of the chart stack the layer draws into; the width is the viewport's.
    let height: CGFloat
    var alignment: Alignment = .topLeading
    let content: (ChartViewport) -> Content

    var animatableData: Double {
        get { viewport.animatableTime }
        set { viewport.animatableTime = newValue }
    }

    var body: some View {
        content(viewport)
            // Load-bearing: `.offset` does not shrink the canvas's *layout* bounds, so the
            // shell's ZStack is canvas-width (~9x the screen), and an unconstrained sibling
            // inherits that width — which is how three axis-overlay attempts rendered
            // "nothing", their trailing-aligned content thousands of points off-screen.
            .frame(width: viewport.viewportWidth, height: height, alignment: alignment)
            .allowsHitTesting(false)
    }
}
