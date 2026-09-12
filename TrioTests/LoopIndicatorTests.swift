import Foundation
import SwiftUI
import Testing
@testable import Trio

@Suite("Loop Indicator") struct LoopIndicatorTests {
    private func color(
        _ automation: AutomationLevel,
        deviceIssue: Bool = false,
        enacted: Bool = true,
        secondsSinceLoop: TimeInterval = 60,
        manualTempBasal: Bool = false
    ) -> Color {
        LoopView.ringColor(
            automation: automation,
            manualTempBasal: manualTempBasal,
            hasDeviceIssue: deviceIssue,
            hasEnactedDetermination: enacted,
            secondsSinceLastLoop: secondsSinceLoop
        )
    }

    @Test("Open loop is green while devices are reporting, whatever the loop age") func openLoopIsGreen() {
        #expect(color(.off) == .loopGreen)
        // Stale loop age must not colour the ring: nothing is being enacted anyway.
        #expect(color(.off, secondsSinceLoop: 60 * 60) == .loopGreen)
    }

    @Test("Open loop goes red only on a device issue") func openLoopDeviceIssue() {
        #expect(color(.off, deviceIssue: true) == .loopRed)
    }

    @Test("Open loop no longer greys out when nothing was enacted") func openLoopIgnoresEnactment() {
        // The old behaviour returned .secondary here, which is what made the pill permanently grey.
        #expect(color(.off, enacted: false) == .loopGreen)
    }

    @Test("Dosing modes keep loop freshness colouring") func dosingModesUseFreshness() {
        for automation in [AutomationLevel.full, .reductionsOnly, .hypoSuspendOnly] {
            #expect(color(automation, secondsSinceLoop: 60) == .loopGreen)
            #expect(color(automation, secondsSinceLoop: 8 * 60) == .loopYellow)
            #expect(color(automation, secondsSinceLoop: 20 * 60) == .loopRed)
            #expect(color(automation, enacted: false) == .secondary)
            // A device issue alone must not mask loop staleness when Trio is dosing.
            #expect(color(automation, deviceIssue: true, secondsSinceLoop: 60) == .loopGreen)
        }
    }

    @Test("A manual temp basal wins over every mode") func manualTempBasalWins() {
        for automation in AutomationLevel.allTestCases {
            #expect(color(automation, manualTempBasal: true) == .loopManualTemp)
        }
    }

    @Test("The ring opens wider the less Trio may do") func ringGapWidensWithConstraint() {
        let full = LoopView.ringGap(automation: .full, manualTempBasal: false)
        let reductions = LoopView.ringGap(automation: .reductionsOnly, manualTempBasal: false)
        let hypo = LoopView.ringGap(automation: .hypoSuspendOnly, manualTempBasal: false)
        let off = LoopView.ringGap(automation: .off, manualTempBasal: false)

        #expect(full == 0)
        #expect(full < reductions)
        #expect(reductions < hypo)
        #expect(hypo < off)
    }

    @Test("A manual temp basal opens the ring fully") func manualTempBasalOpensRing() {
        #expect(
            LoopView.ringGap(automation: .full, manualTempBasal: true)
                == LoopView.ringGap(automation: .off, manualTempBasal: false)
        )
    }
}

private extension AutomationLevel {
    static var allTestCases: [AutomationLevel] { [.off, .hypoSuspendOnly, .reductionsOnly, .full] }
}
