import CoreData
import SwiftDate
import SwiftUI

// MARK: - Zone E: bottom controls (adjustment panel / bolus progress)

extension Home.RootView {
    var bolusProgressFormatter: NumberFormatter {
        let fractionDigits: Int = switch state.settingsManager.preferences.bolusIncrement {
        case 0.1: 1
        case 0.025: 3
        default: 2
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = 0
        formatter.maximumFractionDigits = fractionDigits
        formatter.minimumFractionDigits = fractionDigits
        formatter.allowsFloats = true
        formatter.roundingIncrement = Double(state.settingsManager.preferences.bolusIncrement) as NSNumber
        return formatter
    }

    func remainingFraction(start: Date?, durationMinutes: Decimal?, indefinite: Bool) -> Double? {
        guard !indefinite, let start = start, let durationMinutes = durationMinutes, durationMinutes > 0 else {
            return nil
        }
        let total = Double(truncating: durationMinutes as NSNumber) * 60
        let elapsed = Date().timeIntervalSince(start)
        guard total > 0 else { return nil }
        return min(max(1 - elapsed / total, 0), 1)
    }

    var overrideRemainingFraction: Double? {
        guard let o = latestOverride.first else { return nil }
        return remainingFraction(start: o.date, durationMinutes: o.duration as Decimal?, indefinite: o.indefinite)
    }

    var tempTargetRemainingFraction: Double? {
        guard let t = latestTempTarget.first else { return nil }
        return remainingFraction(start: t.date, durationMinutes: t.duration as Decimal?, indefinite: false)
    }

    var adjustmentTint: Color? {
        if overrideString != nil { return Color.purple }
        if tempTargetString != nil { return Color.loopGreen }
        return nil
    }

    var adjustmentDescriber: AdjustmentDescriber? {
        guard let settingsManager = state.settingsManager else {
            return nil
        }
        return AdjustmentDescriber(
            units: state.units,
            maxSMBBasalMinutes: settingsManager.preferences.maxSMBBasalMinutes,
            maxUAMSMBBasalMinutes: settingsManager.preferences.maxUAMSMBBasalMinutes,
            settingHalfBasalTarget: state.settingHalfBasalTarget,
            autosensMax: state.autosensMax,
            isExerciseModeActive: state.isExerciseModeActive,
            highTTraisesSens: state.highTTraisesSens,
            lowTTlowersSens: state.lowTTlowersSens
        )
    }

    var overrideString: String? {
        guard let latestOverride = latestOverride.first, let describer = adjustmentDescriber else {
            return nil
        }

        if AdjustmentDescriber.isExpired(latestOverride) {
            /// Do not show the Override anymore
            Task {
                guard let objectID = self.latestOverride.first?.objectID else { return }
                await state.cancelOverride(withID: objectID)
            }
        }

        return describer.overrideDetails(latestOverride, showsTarget: tempTargetString == nil)
    }

    var tempTargetString: String? {
        guard let latestTempTarget = latestTempTarget.first, let describer = adjustmentDescriber else {
            return nil
        }

        if AdjustmentDescriber.isExpired(latestTempTarget) {
            /// Do not show the Temp Target anymore
            Task {
                guard let objectID = self.latestTempTarget.first?.objectID else { return }
                await state.cancelTempTarget(withID: objectID)
            }
        }

        return describer.tempTargetDetails(latestTempTarget)
    }

    @ViewBuilder func adjustmentsOverrideView(_ overrideString: String) -> some View {
        AdjustmentLabel.forOverride(
            name: AdjustmentDescriber.name(of: latestOverride.first),
            details: overrideString
        )
    }

    @ViewBuilder func adjustmentsTempTargetView(_ tempTargetString: String) -> some View {
        AdjustmentLabel.forTempTarget(
            name: AdjustmentDescriber.name(of: latestTempTarget.first),
            details: tempTargetString
        )
    }

    @ViewBuilder func adjustmentsCancelView(_ cancelAction: @escaping () -> Void) -> some View {
        Image(systemName: "xmark.app")
            .font(.title)
            .onTapGesture {
                cancelAction()
            }
            .accessibilityLabel(Text("Stop adjustment"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { cancelAction() }
    }

    @ViewBuilder func adjustmentsCancelTempTargetView() -> some View {
        Image(systemName: "xmark.app")
            .font(.title)
            .glassActionSheet(
                "Stop the Temp Target \"\(latestTempTarget.first?.name ?? "")\"?",
                isPresented: $isConfirmStopTempTargetShown,
                actions: [
                    GlassSheetAction("Stop", role: .destructive) {
                        Task {
                            guard let objectID = latestTempTarget.first?.objectID else { return }
                            await state.cancelTempTarget(withID: objectID)
                        }
                    }
                ]
            )
            .padding(.trailing, 8)
            .onTapGesture {
                if !latestTempTarget.isEmpty {
                    isConfirmStopTempTargetShown = true
                }
            }
            .accessibilityLabel(Text("Stop temp target"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if !latestTempTarget.isEmpty {
                    isConfirmStopTempTargetShown = true
                }
            }
    }

    @ViewBuilder func adjustmentsCancelOverrideView() -> some View {
        Image(systemName: "xmark.app")
            .font(.title)
            .glassActionSheet(
                "Stop the Override \"\(latestOverride.first?.name ?? "")\"?",
                isPresented: $isConfirmStopOverridePresented,
                actions: [
                    GlassSheetAction("Stop", role: .destructive) {
                        Task {
                            guard let objectID = latestOverride.first?.objectID else { return }
                            await state.cancelOverride(withID: objectID)
                        }
                    }
                ]
            )
            .padding(.trailing, 8)
            .onTapGesture {
                if !latestOverride.isEmpty {
                    isConfirmStopOverridePresented = true
                }
            }
            .accessibilityLabel(Text("Stop override"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if !latestOverride.isEmpty {
                    isConfirmStopOverridePresented = true
                }
            }
    }

    @ViewBuilder func noActiveAdjustmentsView() -> some View {
        Group {
            AdjustmentIcon(systemName: "slider.horizontal.2.gobackward", tint: Color.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text("No Active Adjustment")
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Profile at 100 %")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()

            // clear icon keeps text aligned with the cancel-button states
            Image(systemName: "xmark.app")
                .font(.title)
                .foregroundStyle(Color.clear)
        }
    }

    // same track pattern as BolusProgressBar, slightly slimmer
    @ViewBuilder func remainingBar(_ fraction: Double?, tint: Color) -> some View {
        GeometryReader { barGeo in
            if let fraction {
                RoundedRectangle(cornerRadius: 15)
                    .fill(tint.opacity(0.85))
                    .frame(width: barGeo.size.width * fraction, height: 4)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(height: 4)
    }

    @ViewBuilder func adjustmentView() -> some View {
        let tint = adjustmentTint
        // concurrent override + temp target: halved tint, one remaining bar per half
        let isConcurrent = overrideString != nil && tempTargetString != nil

        ZStack {
            if isConcurrent {
                // halved tint layer the single-tint glass chrome can't express
                HStack(spacing: 0) {
                    Color.purple.opacity(0.12)
                    Color.loopGreen.opacity(0.12)
                }
                .clipShape(GlassChrome.panelShape)
            }
            HStack {
                if let overrideString = overrideString, let tempTargetString = tempTargetString {
                    // content halves match the tint halves so icons clear the seam
                    HStack(spacing: 0) {
                        HStack {
                            adjustmentsOverrideView(overrideString)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity)

                        HStack {
                            adjustmentsTempTargetView(tempTargetString)
                                .padding(.leading, 8)

                            Spacer(minLength: 0)

                            adjustmentsCancelView({
                                if !latestTempTarget.isEmpty, !latestOverride.isEmpty {
                                    showCancelConfirmDialog = true
                                } else if !latestOverride.isEmpty {
                                    showCancelAlert = true
                                } else if !latestTempTarget.isEmpty {
                                    showCancelAlert = true
                                }
                            })
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else if let overrideString = overrideString {
                    adjustmentsOverrideView(overrideString)
                    Spacer()
                    adjustmentsCancelOverrideView()

                } else if let tempTargetString = tempTargetString {
                    HStack {
                        adjustmentsTempTargetView(tempTargetString)
                        Spacer()
                        adjustmentsCancelTempTargetView()
                    }
                } else {
                    noActiveAdjustmentsView()
                }
            }.padding(.horizontal, 10)
                .glassActionSheet(
                    "Adjustment to Stop",
                    message: Text("Select Adjustment"),
                    isPresented: $showCancelConfirmDialog,
                    actions: [
                        GlassSheetAction("Stop Override", role: .destructive) {
                            Task {
                                guard let objectID = latestOverride.first?.objectID else { return }
                                await state.cancelOverride(withID: objectID)
                            }
                        },
                        GlassSheetAction("Stop Temp Target", role: .destructive) {
                            Task {
                                guard let objectID = latestTempTarget.first?.objectID else { return }
                                await state.cancelTempTarget(withID: objectID)
                            }
                        },
                        GlassSheetAction("Stop All Adjustments", role: .destructive) {
                            Task {
                                guard let overrideObjectID = latestOverride.first?.objectID else { return }
                                await state.cancelOverride(withID: overrideObjectID)

                                guard let tempTargetObjectID = latestTempTarget.first?.objectID else { return }
                                await state.cancelTempTarget(withID: tempTargetObjectID)
                            }
                        }
                    ]
                )
        }
        .frame(height: HomeLayout.bottomPanelHeight)
        .glassPanel(
            tint: isConcurrent ? nil : tint,
            tintOpacity: 0.12,
            strokeOpacity: isConcurrent ? 0 : (tint == nil ? 0.08 : 0.30)
        )
        .overlay(
            // concurrent halves get a bicolor rim the single-tint chrome can't express
            isConcurrent
                ? GlassChrome.panelShape.strokeBorder(
                    LinearGradient(
                        colors: [Color.purple.opacity(0.30), Color.loopGreen.opacity(0.30)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 1
                )
                : nil
        )
        .overlay(alignment: .bottom) {
            // anchored like the bolus progress bar so both panels match
            Group {
                if isConcurrent {
                    HStack(spacing: 6) {
                        remainingBar(overrideRemainingFraction, tint: .purple)
                        remainingBar(tempTargetRemainingFraction, tint: .loopGreen)
                    }
                } else if let tint = tint {
                    remainingBar(overrideRemainingFraction ?? tempTargetRemainingFraction, tint: tint)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 1)
        }
        // whole panel navigates; the cancel buttons' own gestures take precedence
        .contentShape(Rectangle())
        .onTapGesture {
            selectedTab = 2
        }
        .accessibilityHint(Text(String(localized: "Opens adjustments", comment: "Accessibility hint")))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { selectedTab = 2 }
        .padding(.horizontal, 10)
    }

    @ViewBuilder func bolusView(_ progress: Decimal) -> some View {
        /// ensure that state.lastPumpBolus has a value, i.e. there is a last bolus done by the pump and not an external bolus
        /// - TRUE:  show the pump bolus
        /// - FALSE:  do not show a progress bar at all
        if let bolusTotal = state.lastPumpBolus?.bolus?.amount {
            let bolusFraction = progress * (bolusTotal as Decimal)
            let bolusString =
                (bolusProgressFormatter.string(from: bolusFraction as NSNumber) ?? "0")
                    + String(localized: " of ", comment: "Bolus string partial message: 'x U of y U' in home view") +
                    (Formatter.decimalFormatterWithThreeFractionDigits.string(from: bolusTotal as NSNumber) ?? "0")
                    + String(localized: " U", comment: "Insulin unit")
            let bolusLabel = state
                .bolusStatus == .inProgress ? String(localized: "Bolusing") : String(localized: "Initiating…")

            HStack {
                Image(systemName: "cross.vial.fill")
                    .font(.system(size: 25))
                    .accessibilityHidden(true)

                Spacer()

                VStack {
                    Text(bolusLabel)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(bolusString)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.leading, 5)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(bolusLabel))
                    .accessibilityValue(Text(bolusString))

                Spacer()

                if state.bolusStatus == .inProgress {
                    Button {
                        state.showProgressView()
                        state.cancelBolus()
                    } label: {
                        Image(systemName: "xmark.app")
                            .font(.system(size: 25))
                    }
                    .accessibilityLabel(Text("Cancel bolus"))
                } else if state.bolusStatus == .initiating {
                    ProgressView()
                }
            }
            .padding(.horizontal, 10)
            .padding(.trailing, 8)
            .frame(height: HomeLayout.bottomPanelHeight)
            .glassPanel(tint: .insulin, tintOpacity: 0.18, strokeOpacity: 0.30)
            .overlay(alignment: .bottom) {
                // bar hugs the panel's bottom edge (the slot no longer has outer bottom padding)
                BolusProgressBar(progress: progress)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 1)
            }
            .padding(.horizontal, 10)
        }
    }

    func statsDistributionBar(_ segments: [(color: Color, fraction: CGFloat)]) -> some View {
        GeometryReader { g in
            let spacing: CGFloat = 2
            let shown = segments.filter { $0.fraction > 0.005 }
            let available = max(g.size.width - spacing * CGFloat(max(shown.count - 1, 0)), 0)
            HStack(spacing: spacing) {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, segment in
                    Capsule()
                        .fill(segment.color)
                        .frame(width: available * segment.fraction)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func gmiString(_ meanGlucose: Double?) -> String {
        guard let mean = meanGlucose else { return "--" }
        let gmiPercentage = 3.31 + 0.02392 * mean
        // settingsManager is injected after first render; default until then
        if state.settingsManager?.settings.eA1cDisplayUnit == .mmolMol {
            let gmiMmolMol = (gmiPercentage - 2.152) * 10.929
            return "\(Int(gmiMmolMol.rounded())) mmol/mol"
        }
        return gmiPercentage.formatted(.number.precision(.fractionLength(1))) + " %"
    }

    @ViewBuilder func statsBanner() -> some View {
        let face = state.settingsManager?.settings.homeStatsPanelFace ?? .timeInRange
        let range = state.homeStatsPanelRange
        let stats = state.statsPanelStats
        let hasData = stats.hasData
        let averageString = stats.meanGlucose?.formatted(withUnits: state.units) ?? "--"
        let gmiValueString = gmiString(stats.meanGlucose)
        let tirString = hasData
            ? stats.inRangePct.formatted(.number.precision(.fractionLength(0 ... 1))) + " %"
            : "-- %"
        let segments: [(color: Color, fraction: CGFloat)] = hasData ? [
            (.red, CGFloat(stats.veryLowPct / 100)),
            (.orange, CGFloat(stats.lowPct / 100)),
            (.loopGreen, CGFloat(stats.inRangePct / 100)),
            (.purple, CGFloat((stats.highPct + stats.veryHighPct) / 100))
        ] : [(Color.secondary.opacity(0.3), 1)]

        Button {
            state.showModal(for: .statistics)
        } label: {
            ZStack {
                HStack(alignment: .center, spacing: 12) {
                    switch face {
                    case .timeInRange:
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(tirString)
                                    .font(.title2).fontWeight(.bold).fontDesign(.rounded)
                                    .foregroundStyle(.primary)
                                // chart shows 72h; make the reported scope explicit
                                (
                                    Text("Time in Range", comment: "Stats banner subtitle").fontWeight(.semibold)
                                        + Text(" ")
                                        + Text(range.scopeName)
                                )
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            }

                            statsDistributionBar(segments)
                                .frame(height: 6)
                        }
                    case .distributionBar:
                        VStack(alignment: .leading, spacing: 6) {
                            (
                                Text("Time in Range", comment: "Stats banner subtitle").fontWeight(.semibold)
                                    + Text(" ")
                                    + Text(range.scopeName)
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                            statsDistributionBar(segments)
                                .frame(height: 6)
                        }
                    case .averages:
                        VStack(alignment: .leading, spacing: 6) {
                            // "⌀" read as a diameter sign, so spell the label out (#1474)
                            (
                                Text("Avg. Glucose:", comment: "Stats banner label")
                                    + Text(" \(averageString) \u{00B7} GMI \(gmiValueString)")
                            )
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            Text(range.averageSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    case .hidden:
                        Text("View Statistics", comment: "Stats banner hidden face")
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
            }
            .frame(height: HomeLayout.statsBannerHeight)
            .glassPanel()
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var multiUsePanelState: MultiUsePanelState {
        MultiUsePanelState.resolve(
            notificationsDisabled: notificationsDisabled,
            pumpTimeMismatch: state.pumpStatusBadgeImage != nil,
            lastGlucoseDate: state.glucoseFromPersistence.last?.date,
            maxIOB: state.maxIOB,
            hasUnacknowledgedReleaseNotes: releaseNotesService.hasUnacknowledgedNotes,
            dosingMode: state.dosingMode,
            now: state.timerDate
        )
    }

    /// Shared chrome for the non-stats panel states.
    @ViewBuilder func panelBanner(
        systemImage: String,
        title: String,
        subtitle: String,
        tint: Color,
        isCritical: Bool = false,
        tintOpacity: Double? = nil,
        strokeOpacity: Double? = nil,
        strokeWidth: CGFloat? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                HStack(spacing: 12) {
                    AdjustmentIcon(systemName: systemImage, tint: tint)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
            }
            .frame(height: HomeLayout.statsBannerHeight)
            .glassPanel(
                tint: tint,
                tintOpacity: tintOpacity ?? (isCritical ? 0.30 : 0.12),
                strokeOpacity: strokeOpacity ?? (isCritical ? 0.8 : 0.35),
                strokeWidth: strokeWidth ?? (isCritical ? 1.5 : 1)
            )
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// One slot, highest-priority state wins; stats is the default face.
    @ViewBuilder func multiUsePanel() -> some View {
        switch multiUsePanelState {
        case .notificationsDisabled:
            panelBanner(
                systemImage: "bell.slash.fill",
                title: String(localized: "Notifications Disabled"),
                subtitle: String(localized: "Alarms cannot alert you. Tap to fix."),
                tint: .red,
                isCritical: true
            ) {
                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
            }
        case .pumpTimeMismatch:
            panelBanner(
                systemImage: "clock.badge.exclamationmark.fill",
                title: String(localized: "Time Change Detected"),
                subtitle: String(localized: "Pump clock differs from phone. Tap to review."),
                tint: .orange
            ) {
                if state.pumpDisplayState != nil {
                    state.shouldDisplayPumpSetupSheet.toggle()
                }
            }
        case .cgmStale:
            panelBanner(
                systemImage: "drop.fill",
                title: String(localized: "No Recent Glucose"),
                subtitle: String(localized: "Tap to add a fingerstick reading."),
                tint: .orange
            ) {
                showManualGlucose = true
            }
        case .maxIOBZero:
            panelBanner(
                systemImage: "exclamationmark.triangle.fill",
                title: String(localized: "Max IOB is 0 U"),
                subtitle: String(localized: "Automated dosing is limited. Tap to review."),
                tint: .orange
            ) {
                openMaxIOBSetting()
            }
        case .whatsNew:
            panelBanner(
                systemImage: "sparkles",
                title: String(
                    localized: "New Release v\(releaseNotesService.notes?.version ?? "")",
                    comment: "Home panel title offering the release notes; the placeholder is a version number"
                ),
                subtitle: String(localized: "See what's new in this version."),
                tint: .insulin,
                tintOpacity: 0.24,
                strokeOpacity: 0.7,
                strokeWidth: 1.5
            ) {
                showReleaseNotes = true
            }
        case let .dosingModeLimited(mode):
            panelBanner(
                systemImage: mode.icon,
                title: mode.displayName,
                subtitle: mode.miniHint,
                tint: .orange
            ) {
                openDosingModeSetting()
            }
        case .stats:
            statsBanner()
        }
    }

    /// The mode picker sits on the Settings root, so there is no sub-screen target to push.
    func openDosingModeSetting() {
        selectedTab = 3
    }

    func openMaxIOBSetting() {
        // same target search results push, so scroll + highlight wiggle match
        selectedTab = 3
        settingsPath.append(SearchResultTarget(
            screen: .unitsAndLimits,
            scrollLabel: "Maximum Insulin on Board (IOB)".localized
        ))
    }

    /// Bottom-anchored fixed zone: adjustment/bolus panel above the stats banner.
    @ViewBuilder func bottomControls() -> some View {
        VStack(spacing: HomeLayout.bottomZonePadding) {
            Group {
                if let progress = state.bolusProgress {
                    bolusView(progress)
                } else {
                    adjustmentView()
                }
            }
            .frame(height: HomeLayout.bottomPanelHeight)
            .animation(.easeInOut(duration: 0.2), value: state.bolusProgress != nil)

            multiUsePanel()
                .frame(height: HomeLayout.statsBannerHeight)
        }
        .padding(.vertical, HomeLayout.bottomZonePadding)
    }
}
