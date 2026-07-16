import Charts
import CoreData
import SwiftUI

let calendar = Calendar.current

/// Shared generator for the light tick emitted when a scrub lands on a glucose reading.
/// File-scoped so it isn't a stored view property (which would be re-created per body
/// evaluation) and stays prepared across ticks.
private let scrubPointHaptic = UISelectionFeedbackGenerator()

/// The Home screen chart stack (basal / glucose / COB-IOB).
///
/// Rendering strategy: the three charts are laid out ONCE per (data, zoom) change onto a
/// wide fixed canvas spanning the full chart domain — the same render economics as the
/// original ScrollView implementation, which is the only approach that stays smooth at
/// real-world data volumes. Panning translates that canvas with a pure `.offset` transform
/// (zero re-layout), driven by this shell's gesture layer: one-finger drag pans (with
/// momentum), two-finger magnify zooms continuously, and a stationary press inspects.
/// Gestures work identically over all three strips, which also makes desync between the
/// strips structurally impossible.
///
/// `MainChartCanvas` is deliberately a separate child view whose stored properties do NOT
/// include the pan position; SwiftUI therefore skips its body while panning, so the chart
/// content is never re-evaluated mid-gesture.
struct MainChartView: View {
    var geo: GeometryProxy
    /// Height allocated to the chart stack by the Home layout (the flexible
    /// remainder after the fixed zones).
    var chartHeight: CGFloat
    var units: GlucoseUnits
    var highGlucose: Decimal
    var lowGlucose: Decimal
    var currentGlucoseTarget: Decimal
    var glucoseColorScheme: GlucoseColorScheme
    var displayXgridLines: Bool
    var displayYgridLines: Bool
    var thresholdLines: Bool
    var state: Home.StateModel

    @Environment(\.colorScheme) var colorScheme

    /// Date under the user's finger while inspecting (transient popover), else nil.
    @State var selection: Date? = nil

    @State var mainChartHasInitialized = false

    // MARK: - Continuous zoom / pan state

    /// Length of the visible x-axis window in seconds. Driven exclusively by the pinch gesture.
    @State var visibleSeconds: TimeInterval = MainChartHelper.Config.defaultVisibleSeconds

    /// Date at the leading (left) edge of the visible window. Owned by the gesture layer;
    /// panning only changes this value, which translates the pre-laid-out canvas.
    @State var scrollPosition = Date.now
        .addingTimeInterval(-MainChartHelper.Config.defaultVisibleSeconds)

    /// Captured at pinch start so the zoom stays anchored under the pinch centroid.
    @State private var pinchAnchor: (
        visibleAtStart: TimeInterval,
        anchorDate: Date,
        anchorFraction: CGFloat
    )?

    /// Leading edge captured when a one-finger drag transitions from inspecting to panning.
    @State private var panBaseline: Date?

    /// True once a held press has engaged inspect; from then on finger movement scrubs
    /// the selection instead of panning, until the finger lifts.
    @State private var isInspectLatched = false

    /// Most recent finger location, so the hold timer can place the selection even if the
    /// finger produced no further events after touch-down.
    @State private var lastTouchLocation: CGPoint?

    /// Armed at touch-down; fires after `Config.inspectHoldDelay` and latches inspect if
    /// the touch is still down and stationary. A timer is required because `DragGesture`
    /// only reports *changes* — a perfectly still finger generates no events after
    /// touch-down, so the hold can never be detected from inside `onChanged` alone.
    @State private var inspectHoldTask: Task<Void, Never>?

    /// Timestamp of the current touch-down; inspect only engages after
    /// `Config.inspectHoldDelay` of resting, so starting a drag never triggers it.
    @State private var touchDownTime: Date?

    /// Drives post-flick deceleration; cancelled by any new touch or data-driven scroll.
    @State private var momentumTask: Task<Void, Never>?

    /// Auto-pans the chart while a scrubbing finger rests in the viewport's edge zones.
    @State private var edgePanTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .topLeading) {
            MainChartCanvas(
                state: state,
                units: units,
                highGlucose: highGlucose,
                lowGlucose: lowGlucose,
                currentGlucoseTarget: currentGlucoseTarget,
                glucoseColorScheme: glucoseColorScheme,
                displayXgridLines: displayXgridLines,
                displayYgridLines: displayYgridLines,
                thresholdLines: thresholdLines,
                visibleSeconds: visibleSeconds,
                canvasWidth: canvasWidth,
                basalHeight: basalHeight,
                mainHeight: mainHeight,
                cobIobHeight: cobIobHeight,
                glucoseYDomain: paddedGlucoseYDomain
            )
            .equatable()
            .offset(x: -canvasOffsetX)

            nowOffscreenGradient

            // Pinned y-axis labels over the glucose pane, ABOVE the scrolled-back gradient
            // so the labels are never dimmed by it. Pure overlay; never re-lays the canvas.
            // CRITICAL: the explicit viewport-width frame below is load-bearing. `.offset`
            // does not shrink the canvas's *layout* bounds, so this ZStack is canvas-width
            // (~9x the screen); an unconstrained sibling inherits that width and its
            // trailing-aligned content renders thousands of points off-screen — which is
            // exactly how three axis-overlay attempts rendered "nothing".
            VStack(spacing: 0) {
                Color.clear.frame(height: basalHeight)
                StaticYAxisChart(
                    yDomain: paddedGlucoseYDomain,
                    units: units,
                    displayYgridLines: displayYgridLines
                )
                .equatable()
                .frame(height: mainHeight)
                // Keep the axis labels off the screen edge.
                .padding(.trailing, 4)
                Color.clear.frame(height: cobIobHeight)
            }
            .frame(width: viewportWidth, height: stackHeight, alignment: .topLeading)
            .allowsHitTesting(false)

            selectionOverlay
                .allowsHitTesting(false)
        }
        .frame(
            width: viewportWidth,
            height: basalHeight + mainHeight + cobIobHeight,
            alignment: .topLeading
        )
        .clipped()
        .contentShape(Rectangle())
        .simultaneousGesture(panAndInspectGesture)
        .simultaneousGesture(magnifyGesture)
        .simultaneousGesture(TapGesture(count: 2).onEnded { cycleZoomPreset() })
        .onDisappear {
            momentumTask?.cancel()
            inspectHoldTask?.cancel()
            edgePanTask?.cancel()
        }
        .onChange(of: state.glucoseFromPersistence.last?.glucose) {
            state.updateStartEndMarkers()
            scrollToTrailingEdge()
        }
        .onChange(of: state.enactedAndNonEnactedDeterminations.first?.deliverAt) {
            scrollToTrailingEdge()
        }
        .onChange(of: units) {
            // TODO: - Refactor this to only update the Y Axis Scale
            state.setupGlucoseArray()
        }
        .onAppear {
            if !mainChartHasInitialized {
                state.updateStartEndMarkers()
                scrollToTrailingEdge()
                mainChartHasInitialized = true
            }
        }
    }
}

// MARK: - Layout metrics

extension MainChartView {
    private var viewportWidth: CGFloat { max(geo.size.width, 1) }

    // Pane splits of the chart's own allocation, preserving the proportions
    // of the previous screen-height fractions (0.05 / 0.33 / 0.12 = 10% /
    // 66% / 24% of the 50% chart block).
    var basalHeight: CGFloat { chartHeight * 0.10 }
    var mainHeight: CGFloat { chartHeight * 0.66 }
    var cobIobHeight: CGFloat { chartHeight * 0.24 }

    private var totalSeconds: TimeInterval {
        max(state.endMarker.timeIntervalSince(state.startMarker), 1)
    }

    /// Width of the full pre-laid-out canvas: the viewport shows `visibleSeconds` of the
    /// `totalSeconds` domain, so the canvas is proportionally wider than the viewport.
    private var canvasWidth: CGFloat {
        viewportWidth * CGFloat(totalSeconds / visibleSeconds)
    }

    /// Pixel offset of the canvas for the current leading-edge date.
    private var canvasOffsetX: CGFloat {
        CGFloat(scrollPosition.timeIntervalSince(state.startMarker) / totalSeconds) * canvasWidth
    }

    /// Glucose y-domain padded above and below so values at the data extremes (and the carb
    /// markers `CarbView` pins to the old baseline) render fully instead of straddling the
    /// plot edge. Also gives the plot visual breathing room at top and bottom.
    var paddedGlucoseYDomain: ClosedRange<Decimal> {
        let padding: Decimal = 25 // mg/dL
        let lower = state.minYAxisValue - padding
        let upper = state.maxYAxisValue + padding
        return units == .mgdL ? lower ... upper : lower.asMmolL ... upper.asMmolL
    }
}

// MARK: - Selection lookup (shell-owned; the canvas knows nothing about selection)

extension MainChartView {
    var selectedGlucose: GlucoseStored? {
        guard let selection = selection else { return nil }
        let range = selection.addingTimeInterval(-150) ... selection.addingTimeInterval(150)
        return state.glucoseFromPersistence.first { $0.date.map(range.contains) ?? false }
    }

    private func findDetermination(in range: ClosedRange<Date>) -> OrefDetermination? {
        let now = Date.now
        return state.enactedAndNonEnactedDeterminations.first {
            $0.deliverAt ?? now >= range.lowerBound && $0.deliverAt ?? now <= range.upperBound
        }
    }

    var selectedCOBValue: OrefDetermination? {
        guard let selection = selection else { return nil }
        let range = selection.addingTimeInterval(-150) ... selection.addingTimeInterval(150)
        return findDetermination(in: range)
    }

    var selectedIOBValue: OrefDetermination? {
        guard let selection = selection else { return nil }
        let range = selection.addingTimeInterval(-150) ... selection.addingTimeInterval(150)
        return findDetermination(in: range)
    }
}

// MARK: - Selection overlay (rendered in the shell, never re-lays the canvas)

extension MainChartView {
    private var stackHeight: CGFloat { basalHeight + mainHeight + cobIobHeight }

    private func xPosition(for date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(scrollPosition) / visibleSeconds) * viewportWidth
    }

    private func glucoseYPosition(for glucose: GlucoseStored) -> CGFloat {
        let value = units == .mgdL ? Decimal(glucose.glucose) : Decimal(glucose.glucose).asMmolL
        let domain = paddedGlucoseYDomain
        let span = domain.upperBound - domain.lowerBound
        let fraction = span == 0 ? 0.5 :
            Double(truncating: ((value - domain.lowerBound) / span) as NSDecimalNumber)
        return basalHeight + mainHeight * CGFloat(1 - min(max(fraction, 0), 1))
    }

    private func cobIobYPosition(forChartValue value: Double) -> CGFloat {
        let domain = MainChartHelper.cobIobYDomain(
            minCob: state.minValueCobChart,
            maxCob: state.maxValueCobChart,
            minIob: state.minValueIobChart,
            maxIob: state.maxValueIobChart
        )
        let span = domain.upperBound - domain.lowerBound
        let fraction = span == 0 ? 0.5 : (value - domain.lowerBound) / span
        return basalHeight + mainHeight + cobIobHeight * CGFloat(1 - min(max(fraction, 0), 1))
    }

    /// Dark fade pinned to the trailing edge whenever "now" is scrolled off-screen.
    /// Without it, yesterday's 2 am and today's 2 am are visually indistinguishable; the
    /// fade signals "you are looking at the past — newer data lies this way". Opacity
    /// ramps in over the first 30 min of scroll-back so it doesn't pop at the boundary.
    @ViewBuilder private var nowOffscreenGradient: some View {
        let trailingEdge = scrollPosition.addingTimeInterval(visibleSeconds)
        let secondsBehindNow = Date.now.timeIntervalSince(trailingEdge)
        let color: Color = (colorScheme == .dark ? Color.bgDarkerDarkBlue : Color.black.opacity(0.25))
        if secondsBehindNow > 0 {
            let strength = min(1.0, secondsBehindNow / 1800)
            LinearGradient(
                colors: [color.opacity(0), color.opacity(0.8 * strength)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 120, height: stackHeight)
            .frame(width: viewportWidth, alignment: .trailing)
            .allowsHitTesting(false)
        }
    }

    /// Vertical indicator + point highlights + detail card for the current selection.
    /// Positions are computed with the same linear maps the canvas charts use, and the
    /// card sits in a fixed slot at the top of the glucose pane, inside the viewport —
    /// so it can never be clipped.
    @ViewBuilder private var selectionOverlay: some View {
        if let selectedGlucose, let selectionDate = selectedGlucose.date {
            let x = xPosition(for: selectionDate)
            if x >= 0, x <= viewportWidth {
                let markColor = selectionMarkColor(
                    for: selectedGlucose,
                    highGlucose: highGlucose,
                    lowGlucose: lowGlucose,
                    currentGlucoseTarget: currentGlucoseTarget,
                    glucoseColorScheme: glucoseColorScheme
                )
                let glucoseY = glucoseYPosition(for: selectedGlucose)

                // Vertical indicator through all three panes.
                Rectangle()
                    .fill(Color.tabBar)
                    .frame(width: 2, height: stackHeight)
                    .position(x: x, y: stackHeight / 2)

                // Selected glucose highlight.
                Circle().fill(markColor)
                    .frame(width: 15, height: 15)
                    .position(x: x, y: glucoseY)
                Circle().fill(Color.primary)
                    .frame(width: 6, height: 6)
                    .position(x: x, y: glucoseY)

                // Selected COB / (scaled) IOB dots on the bottom pane.
                if let selectedCOBValue {
                    let y = cobIobYPosition(forChartValue: Double(selectedCOBValue.cob))
                    Circle().fill(Color.orange.opacity(0.8))
                        .frame(width: 15, height: 15)
                        .position(x: x, y: y)
                    Circle().fill(Color.primary)
                        .frame(width: 6, height: 6)
                        .position(x: x, y: y)
                }
                if let selectedIOBValue {
                    let scaled = MainChartHelper.scaledIobAmount(selectedIOBValue.iob?.doubleValue ?? 0)
                    let y = cobIobYPosition(forChartValue: scaled)
                    Circle().fill(Color.darkerBlue.opacity(0.8))
                        .frame(width: 15, height: 15)
                        .position(x: x, y: y)
                    Circle().fill(Color.primary)
                        .frame(width: 6, height: 6)
                        .position(x: x, y: y)
                }

                // Detail card: fixed slot at the top of the glucose pane.
                VStack(spacing: 0) {
                    Color.clear.frame(height: basalHeight + 4)
                    SelectionPopoverView(
                        selectedGlucose: selectedGlucose,
                        selectedIOBValue: selectedIOBValue,
                        selectedCOBValue: selectedCOBValue,
                        units: units,
                        highGlucose: highGlucose,
                        lowGlucose: lowGlucose,
                        currentGlucoseTarget: currentGlucoseTarget,
                        glucoseColorScheme: glucoseColorScheme,
                        isSmoothingEnabled: state.settingsManager.settings.smoothGlucose
                    )
                    Spacer(minLength: 0)
                }
                .frame(width: viewportWidth)
            }
        }
    }
}

// MARK: - Zoom / pan / inspect gesture handling

extension MainChartView {
    private var isPinching: Bool { pinchAnchor != nil }

    /// Converts a horizontal translation (pt) into a time delta within the visible window.
    private func timeDelta(forTranslation dx: CGFloat) -> TimeInterval {
        TimeInterval(dx / viewportWidth) * visibleSeconds
    }

    /// The date under a given x position (in the viewport's coordinate space).
    private func date(atViewportX x: CGFloat) -> Date {
        let fraction = min(max(x / viewportWidth, 0), 1)
        return scrollPosition.addingTimeInterval(visibleSeconds * TimeInterval(fraction))
    }

    /// Keeps domain-edge content clear of the pinned y-axis labels.
    private var trailingOverscan: TimeInterval { visibleSeconds * 0.05 }

    /// Double-tap cycles the zoom presets, trailing edge anchored.
    private func cycleZoomPreset() {
        let presets = MainChartHelper.Config.zoomPresets
        let next = presets.first(where: { $0 > visibleSeconds + 1 }) ?? presets[0]
        let trailing = scrollPosition.addingTimeInterval(visibleSeconds)
        momentumTask?.cancel()
        withAnimation(.easeInOut(duration: 0.25)) {
            visibleSeconds = next
            scrollPosition = clampedLeadingEdge(trailing.addingTimeInterval(-next))
        }
    }

    /// Clamps a proposed leading edge so the visible window never leaves the chart's domain.
    private func clampedLeadingEdge(_ proposed: Date) -> Date {
        let earliest = state.startMarker
        let latest = state.endMarker.addingTimeInterval(trailingOverscan - visibleSeconds)
        return min(max(proposed, earliest), max(earliest, latest))
    }

    /// Anchors the visible window just past `state.endMarker`.
    private func scrollToTrailingEdge() {
        // Never yank the chart out from under an active gesture (pan, pinch, or an
        // in-progress inspect/scrub); the next data tick after the gesture ends will
        // re-anchor to trailing as before.
        guard !isPinching, panBaseline == nil, !isInspectLatched else { return }
        momentumTask?.cancel()
        scrollPosition = state.endMarker.addingTimeInterval(trailingOverscan - visibleSeconds)
    }

    /// One-finger gesture: movement pans (with momentum on release); a press held in
    /// place for `Config.inspectHoldDelay` latches into inspect, after which dragging
    /// scrubs the selection until the finger lifts. Selection is rendered by a shell
    /// overlay and panning only mutates `scrollPosition` (a transform), so neither path
    /// ever re-lays the canvas.
    private var panAndInspectGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                momentumTask?.cancel()
                guard !isPinching else {
                    inspectHoldTask?.cancel()
                    edgePanTask?.cancel()
                    if selection != nil { selection = nil }
                    panBaseline = nil
                    touchDownTime = nil
                    isInspectLatched = false
                    return
                }
                lastTouchLocation = value.location
                if touchDownTime == nil {
                    touchDownTime = value.time
                    scheduleInspectHold()
                }

                // Once inspect has engaged, the rest of this touch scrubs the selection —
                // selection is rendered by a shell overlay, so scrubbing never re-lays
                // the canvas and stays gesture-rate smooth.
                if isInspectLatched {
                    updateSelection(atViewportX: value.location.x)
                    manageEdgePan(atViewportX: value.location.x)
                    return
                }

                let distance = hypot(value.translation.width, value.translation.height)
                if panBaseline == nil, distance < MainChartHelper.Config.inspectMovementTolerance {
                    // Finger is stationary: nothing to do here — the hold timer armed at
                    // touch-down will latch inspect if it stays that way.
                } else {
                    // Finger is travelling: pan. The touch can no longer become an inspect.
                    inspectHoldTask?.cancel()
                    if selection != nil { selection = nil }
                    if panBaseline == nil {
                        // Compensate for the distance already travelled inside the
                        // tolerance so the pan engages without a positional jump.
                        panBaseline = scrollPosition
                            .addingTimeInterval(timeDelta(forTranslation: value.translation.width))
                    }
                    if let baseline = panBaseline {
                        scrollPosition = clampedLeadingEdge(
                            baseline.addingTimeInterval(-timeDelta(forTranslation: value.translation.width))
                        )
                    }
                }
            }
            .onEnded { value in
                inspectHoldTask?.cancel()
                edgePanTask?.cancel()
                if selection != nil { selection = nil }
                touchDownTime = nil
                isInspectLatched = false
                lastTouchLocation = nil
                let wasPanning = panBaseline != nil
                panBaseline = nil
                guard wasPanning, !isPinching else { return }
                // Momentum: initial velocity in seconds of chart time per second.
                let velocity = -timeDelta(forTranslation: value.velocity.width)
                startMomentum(velocitySecondsPerSecond: velocity)
            }
    }

    /// Arms the inspect hold: after `Config.inspectHoldDelay`, if the touch is still down
    /// and has neither become a pan nor a pinch, latch into inspect mode at the finger's
    /// last known position — with a haptic tick so the mode change is felt.
    private func scheduleInspectHold() {
        inspectHoldTask?.cancel()
        inspectHoldTask = Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: UInt64(MainChartHelper.Config.inspectHoldDelay * 1_000_000_000)
            )
            guard !Task.isCancelled,
                  touchDownTime != nil, // finger still down
                  panBaseline == nil, // touch has not become a pan
                  !isPinching,
                  !isInspectLatched
            else { return }

            isInspectLatched = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            scrubPointHaptic.prepare()
            if let location = lastTouchLocation {
                updateSelection(atViewportX: location.x, withPointHaptic: false)
            }
        }
    }

    /// Snaps a viewport x position to the 5-minute glucose cadence and updates the
    /// selection, skipping no-op writes. The popover lookup window is +/-150 s, so the
    /// 300 s snap lands exactly on the nearest reading; it also means finger jitter or a
    /// scrub only produces a new value when actually crossing to another reading.
    private func updateSelection(atViewportX x: CGFloat, withPointHaptic: Bool = true) {
        let raw = date(atViewportX: x)
        let quantum: TimeInterval = 300
        let snapped = Date(
            timeIntervalSince1970: (raw.timeIntervalSince1970 / quantum).rounded() * quantum
        )
        guard selection != snapped else { return }
        selection = snapped
        // A featherlight tick whenever the scrub lands on an actual glucose reading.
        if withPointHaptic, hasGlucoseReading(near: snapped) {
            scrubPointHaptic.selectionChanged()
            scrubPointHaptic.prepare()
        }
    }

    /// Whether a glucose reading exists within the selection matching window of `date`.
    private func hasGlucoseReading(near date: Date) -> Bool {
        let range = date.addingTimeInterval(-150) ... date.addingTimeInterval(150)
        return state.glucoseFromPersistence.contains { $0.date.map(range.contains) ?? false }
    }

    /// While scrubbing, a finger resting in the viewport's edge zones auto-pans the chart
    /// so the scrub can continue into off-screen data. Speed scales with edge depth; only
    /// `scrollPosition` (a transform) and the overlay selection are mutated, so this runs
    /// at frame rate without touching the canvas.
    private func manageEdgePan(atViewportX x: CGFloat) {
        let zone = MainChartHelper.Config.edgePanZoneWidth
        let inZone = x < zone || x > viewportWidth - zone
        guard inZone else {
            edgePanTask?.cancel()
            edgePanTask = nil
            return
        }
        guard edgePanTask == nil else { return }
        edgePanTask = Task { @MainActor in
            let frameDuration: TimeInterval = 1.0 / 60.0
            while !Task.isCancelled, isInspectLatched {
                guard let fingerX = lastTouchLocation?.x else { break }
                let leftDepth = max(0, zone - fingerX) / zone
                let rightDepth = max(0, fingerX - (viewportWidth - zone)) / zone
                let depth = max(leftDepth, rightDepth)
                guard depth > 0 else { break }

                let direction: TimeInterval = rightDepth > 0 ? 1 : -1
                let speed = TimeInterval(depth) * visibleSeconds * 0.5 // chart-seconds per second
                let next = clampedLeadingEdge(
                    scrollPosition.addingTimeInterval(direction * speed * frameDuration)
                )
                guard next != scrollPosition else { break } // domain edge reached
                scrollPosition = next
                updateSelection(atViewportX: fingerX)

                try? await Task.sleep(nanoseconds: UInt64(frameDuration * 1_000_000_000))
            }
            edgePanTask = nil
        }
    }

    /// Deceleration after a flick. Mutates only `scrollPosition` (a transform), so each
    /// frame costs a GPU translation — the same cost profile as live panning.
    private func startMomentum(velocitySecondsPerSecond initialVelocity: TimeInterval) {
        // Ignore tiny flicks.
        guard abs(initialVelocity) > visibleSeconds * 0.05 else { return }
        momentumTask?.cancel()
        momentumTask = Task { @MainActor in
            var velocity = initialVelocity
            let frameDuration: TimeInterval = 1.0 / 60.0
            let decayPerFrame = 0.97
            while !Task.isCancelled, abs(velocity) > visibleSeconds * 0.02 {
                try? await Task.sleep(nanoseconds: UInt64(frameDuration * 1_000_000_000))
                guard !Task.isCancelled else { return }
                let next = clampedLeadingEdge(scrollPosition.addingTimeInterval(velocity * frameDuration))
                guard next != scrollPosition else { return } // hit a domain edge
                scrollPosition = next
                velocity *= decayPerFrame
            }
        }
    }

    /// Two-finger pinch drives the zoom level continuously, anchored under the pinch
    /// centroid. Zoom changes re-lay the canvas, so commits are quantized to a geometric
    /// grid (`Config.zoomStepRatio`) to bound the number of re-layouts per pinch.
    private var magnifyGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                momentumTask?.cancel()
                if pinchAnchor == nil {
                    let fraction = min(max(value.startAnchor.x, 0), 1)
                    pinchAnchor = (
                        visibleAtStart: visibleSeconds,
                        anchorDate: scrollPosition.addingTimeInterval(visibleSeconds * fraction),
                        anchorFraction: fraction
                    )
                }
                guard let pinch = pinchAnchor, value.magnification > 0 else { return }

                // Pinch out (magnification > 1) narrows the visible window, i.e. zooms in.
                var proposed = pinch.visibleAtStart / TimeInterval(value.magnification)
                proposed = min(
                    max(proposed, MainChartHelper.Config.minVisibleSeconds),
                    MainChartHelper.Config.maxVisibleSeconds
                )
                // Snap to the geometric zoom grid (~4 % steps): a full halving of the
                // window costs ~18 canvas re-layouts instead of hundreds.
                let ratio = MainChartHelper.Config.zoomStepRatio
                let step = (log(proposed / MainChartHelper.Config.defaultVisibleSeconds) / log(ratio)).rounded()
                proposed = MainChartHelper.Config.defaultVisibleSeconds * pow(ratio, step)
                proposed = min(
                    max(proposed, MainChartHelper.Config.minVisibleSeconds),
                    MainChartHelper.Config.maxVisibleSeconds
                )

                guard proposed != visibleSeconds else {
                    // Still keep the anchor pinned while between grid steps.
                    scrollPosition = clampedLeadingEdge(
                        pinch.anchorDate.addingTimeInterval(-visibleSeconds * pinch.anchorFraction)
                    )
                    return
                }

                visibleSeconds = proposed
                scrollPosition = clampedLeadingEdge(
                    pinch.anchorDate.addingTimeInterval(-proposed * pinch.anchorFraction)
                )
            }
            .onEnded { _ in
                pinchAnchor = nil
            }
    }
}

// MARK: - Pinned y-axis overlay

/// Chart that renders only the glucose y-axis — the original `mainChartYAxis` content,
/// verbatim — at a fixed position over the scrolling canvas. This is the successor of the
/// old "dummy chart" overlay. It rendered "nothing" during this refactor only because its
/// container inherited the canvas's layout width and drew the trailing labels thousands of
/// points off-screen; with the container pinned to the viewport (see the load-bearing frame
/// at the call site), the pattern works as it always did.
struct StaticYAxisChart: View {
    let yDomain: ClosedRange<Decimal>
    let units: GlucoseUnits
    let displayYgridLines: Bool

    var body: some View {
        Chart {
            // Invisible content at the domain corners so both scales are resolvable and
            // the plot (and with it the axis) materializes.
            PointMark(x: .value("Edge", 0.0), y: .value("Min", yDomain.lowerBound))
                .opacity(0)
            PointMark(x: .value("Edge", 1.0), y: .value("Max", yDomain.upperBound))
                .opacity(0)
        }
        .chartXScale(domain: 0.0 ... 1.0)
        .chartYScale(domain: yDomain)
        .chartXAxis(.hidden)
        .chartYAxis { mainChartYAxis }
        .chartLegend(.hidden)
    }

    private var mainChartYAxis: some AxisContent {
        AxisMarks(position: .trailing) { value in
            if displayYgridLines {
                AxisGridLine(stroke: .init(lineWidth: 0.5, dash: [2, 3]))
            } else {
                AxisGridLine(stroke: .init(lineWidth: 0, dash: [2, 3]))
            }
            if let glucoseValue = value.as(Double.self), glucoseValue > 0 {
                /// fix offset between the two charts...
                if units == .mmolL {
                    AxisTick(length: 7, stroke: .init(lineWidth: 7)).foregroundStyle(Color.clear)
                }
                AxisValueLabel().font(.footnote).foregroundStyle(Color.primary)
            }
        }
    }
}

// MARK: - Canvas (laid out once per data / zoom change; translated while panning)

struct MainChartCanvas: View {
    var state: Home.StateModel
    var units: GlucoseUnits
    var highGlucose: Decimal
    var lowGlucose: Decimal
    var currentGlucoseTarget: Decimal
    var glucoseColorScheme: GlucoseColorScheme
    var displayXgridLines: Bool
    var displayYgridLines: Bool
    var thresholdLines: Bool
    var visibleSeconds: TimeInterval
    var canvasWidth: CGFloat
    var basalHeight: CGFloat
    var mainHeight: CGFloat
    var cobIobHeight: CGFloat
    var glucoseYDomain: ClosedRange<Decimal>

    @State var basalProfiles: [BasalProfile] = []
    @State var preparedTempBasals: [(start: Date, end: Date, rate: Double)] = []

    // Computed (not stored) on purpose: stored properties participate in SwiftUI's
    // change detection, and a stored reference initialized per-init could mark this view
    // as "changed" on every parent body evaluation — i.e. on every pan frame — defeating
    // the body skip this whole architecture depends on.
    var context: NSManagedObjectContext { CoreDataStack.shared.persistentContainer.viewContext }

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.calendar) var calendar

    var upperLimit: Decimal {
        units == .mgdL ? 400 : 22.2
    }

    var body: some View {
        VStack(spacing: 0) {
            basalChart
            mainChart
            cobIobChart
        }
        .frame(width: canvasWidth)
        .onAppear {
            calculateTempBasals()
        }
    }
}

// MARK: - Main (glucose) chart pane with selection popover

extension MainChartCanvas {
    var mainChart: some View {
        Chart {
            drawCurrentTimeMarker()
            drawThresholdLines()

            GlucoseTargetsView(
                targetProfiles: state.targetProfiles
            )

            OverrideView(
                state: state,
                overrides: state.overrides,
                overrideRunStored: state.overrideRunStored,
                units: state.units,
                viewContext: context
            )

            TempTargetView(
                tempTargetStored: state.tempTargetStored,
                tempTargetRunStored: state.tempTargetRunStored,
                units: state.units,
                viewContext: context
            )

            GlucoseChartView(
                glucoseData: state.glucoseFromPersistence,
                units: state.units,
                highGlucose: state.highGlucose,
                lowGlucose: state.lowGlucose,
                currentGlucoseTarget: state.currentGlucoseTarget,
                isSmoothingEnabled: state.isSmoothingEnabled,
                glucoseColorScheme: state.glucoseColorScheme
            )

            InsulinView(
                glucoseData: state.glucoseFromPersistence,
                insulinData: state.insulinFromPersistence,
                units: state.units,
                bolusDisplayThreshold: state.bolusDisplayThreshold
            )

            CarbView(
                glucoseData: state.glucoseFromPersistence,
                units: state.units,
                carbData: state.carbsFromPersistence,
                fpuData: state.fpusFromPersistence,
                minValue: units == .mgdL ? state.minYAxisValue : state.minYAxisValue
                    .asMmolL
            )

            ForecastView(
                preprocessedData: state.preprocessedData,
                minForecast: state.minForecast,
                maxForecast: state.maxForecast,
                units: state.units,
                maxValue: state.maxYAxisValue,
                forecastDisplayType: state.forecastDisplayType,
                lastDeterminationDate: state.determinationsFromPersistence.first?.deliverAt ?? .distantPast
            )
        }
        .frame(width: canvasWidth, height: mainHeight)
        .chartXScale(domain: state.startMarker ... state.endMarker)
        .chartXAxis { mainChartXAxis }
        .chartYAxis(.hidden)
        .chartYScale(domain: glucoseYDomain)
        .chartLegend(.hidden)
        .chartForegroundStyleScale([
            "iob": Color.insulin,
            "uam": Color.uam,
            "zt": Color.zt,
            "cob": Color.orange
        ])
    }
}

// MARK: - Change detection

/// Explicit equality so SwiftUI provably skips the canvas body during panning/momentum
/// (which only change the shell's offset). Data updates still propagate: they arrive via
/// Observation tracking of `state`, which invalidates the body independently of this check.
extension MainChartCanvas: Equatable {
    static func == (lhs: MainChartCanvas, rhs: MainChartCanvas) -> Bool {
        lhs.state === rhs.state &&
            lhs.units == rhs.units &&
            lhs.highGlucose == rhs.highGlucose &&
            lhs.lowGlucose == rhs.lowGlucose &&
            lhs.currentGlucoseTarget == rhs.currentGlucoseTarget &&
            lhs.glucoseColorScheme == rhs.glucoseColorScheme &&
            lhs.displayXgridLines == rhs.displayXgridLines &&
            lhs.displayYgridLines == rhs.displayYgridLines &&
            lhs.thresholdLines == rhs.thresholdLines &&
            lhs.visibleSeconds == rhs.visibleSeconds &&
            lhs.canvasWidth == rhs.canvasWidth &&
            lhs.basalHeight == rhs.basalHeight &&
            lhs.mainHeight == rhs.mainHeight &&
            lhs.cobIobHeight == rhs.cobIobHeight &&
            lhs.glucoseYDomain == rhs.glucoseYDomain
    }
}

extension StaticYAxisChart: Equatable {}
