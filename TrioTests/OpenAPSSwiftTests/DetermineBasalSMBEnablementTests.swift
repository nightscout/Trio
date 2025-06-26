
import Foundation
import Testing
@testable import Trio

@Suite("Determination: SMB Enablement Tests") struct SMBEnablementTests {
    /// Scheduled-off override window should always disable SMB
    @Test("should disable SMB during scheduled-off window") func disableDuringScheduledOff() async throws {
        let now = Calendar.current.date(from: DateComponents(hour: 10))!
        let override = Override(
            name: "scheduledOff",
            enabled: true,
            date: now,
            duration: 0,
            indefinite: false,
            percentage: 1,
            smbIsOff: false,
            isPreset: false,
            id: "",
            overrideTarget: false,
            target: 0,
            advancedSettings: false,
            isfAndCr: false,
            isf: false,
            cr: false,
            smbIsScheduledOff: true,
            start: 9,
            end: 17,
            smbMinutes: 0,
            uamMinutes: 0
        )
        var profile = Profile()
        profile.enableSMBAlways = true
        let bg = BloodGlucose(
            sgv: 120,
            date: Decimal(now.timeIntervalSince1970 * 1000),
            dateString: now
        )
        let autosens = Autosens(ratio: 1, newisf: nil)
        #expect(
            DeterminationGenerator.isSMBEnabled(
                glucose: bg,
                profile: profile,
                autosens: autosens,
                mealData: nil,
                override: override,
                shouldProtectDueToHIGH: false,
                currentTime: now
            ) == false
        )
    }

    /// A hard-off override should disable SMB immediately
    @Test("should disable SMB when override.smbIsOff") func disableWhenOverrideOff() async throws {
        let now = Date()
        let override = Override(
            name: "hardOff",
            enabled: true,
            date: now,
            duration: 0,
            indefinite: false,
            percentage: 1,
            smbIsOff: true,
            isPreset: false,
            id: "",
            overrideTarget: false,
            target: 0,
            advancedSettings: false,
            isfAndCr: false,
            isf: false,
            cr: false,
            smbIsScheduledOff: false,
            start: 0,
            end: 0,
            smbMinutes: 0,
            uamMinutes: 0
        )
        let profile = Profile()
        let bg = BloodGlucose(sgv: 100, date: Decimal(now.timeIntervalSince1970 * 1000), dateString: now)
        let autosens = Autosens(ratio: 1, newisf: nil)
        #expect(
            DeterminationGenerator.isSMBEnabled(
                glucose: bg,
                profile: profile,
                autosens: autosens,
                mealData: nil,
                override: override,
                shouldProtectDueToHIGH: false,
                currentTime: now
            ) == false
        )
    }

    /// Should disable if CGM reports “HIGH” protection
    @Test("should disable SMB when protectDueToHIGH") func disableWhenProtectDueToHIGH() async throws {
        let now = Date()
        let profile = Profile()
        let bg = BloodGlucose(sgv: 150, date: Decimal(now.timeIntervalSince1970 * 1000), dateString: now)
        let autosens = Autosens(ratio: 1, newisf: nil)
        #expect(
            DeterminationGenerator.isSMBEnabled(
                glucose: bg,
                profile: profile,
                autosens: autosens,
                mealData: nil,
                override: nil,
                shouldProtectDueToHIGH: true,
                currentTime: now
            ) == false
        )
    }

    /// Always-on preference should enable SMB
    @Test("should enable SMB when enableSMBAlways") func enableWhenAlwaysEnabled() async throws {
        let now = Date()
        var profile = Profile()
        profile.enableSMBAlways = true
        let bg = BloodGlucose(sgv: 80, date: Decimal(now.timeIntervalSince1970 * 1000), dateString: now)
        let autosens = Autosens(ratio: 1, newisf: nil)
        #expect(
            DeterminationGenerator.isSMBEnabled(
                glucose: bg,
                profile: profile,
                autosens: autosens,
                mealData: nil,
                override: nil,
                shouldProtectDueToHIGH: false,
                currentTime: now
            ) == true
        )
    }

    /// Low temp-target below 100 should enable SMB when allowed
    @Test("should enable SMB with active low temp target") func enableWithActiveLowTempTarget() async throws {
        let now = Date()
        var profile = Profile()
        profile.temptargetSet = true
        profile.enableSMBWithTemptarget = true
        profile.targetBg = 90
        let bg = BloodGlucose(sgv: 95, date: Decimal(now.timeIntervalSince1970 * 1000), dateString: now)
        let autosens = Autosens(ratio: 1, newisf: nil)
        #expect(
            DeterminationGenerator.isSMBEnabled(
                glucose: bg,
                profile: profile,
                autosens: autosens,
                mealData: nil,
                override: nil,
                shouldProtectDueToHIGH: false,
                currentTime: now
            ) == true
        )
    }

    /// High temp-target above 100 should disable SMB when not allowed
    @Test("should disable SMB with high temp target not allowed") func disableWhenHighTempTargetNotAllowed() async throws {
        let now = Date()
        var profile = Profile()
        profile.temptargetSet = true
        profile.allowSMBWithHighTemptarget = false
        profile.targetBg = 120
        let bg = BloodGlucose(sgv: 115, date: Decimal(now.timeIntervalSince1970 * 1000), dateString: now)
        let autosens = Autosens(ratio: 1, newisf: nil)
        #expect(
            DeterminationGenerator.isSMBEnabled(
                glucose: bg,
                profile: profile,
                autosens: autosens,
                mealData: nil,
                override: nil,
                shouldProtectDueToHIGH: false,
                currentTime: now
            ) == false
        )
    }

    /// Carbs-on-board should enable SMB when COB > 0
    @Test("should enable SMB with COB") func enableWithCOB() async throws {
        let now = Date()
        var profile = Profile()
        profile.enableSMBWithCOB = true
        let mealData = ComputedCarbs(
            carbs: 30,
            mealCOB: 10,
            currentDeviation: 0,
            maxDeviation: 0,
            minDeviation: 0,
            slopeFromMaxDeviation: 0,
            slopeFromMinDeviation: 0,
            allDeviations: [0],
            lastCarbTime: now.timeIntervalSince1970
        )
        let bg = BloodGlucose(sgv: 100, date: Decimal(now.timeIntervalSince1970 * 1000), dateString: now)
        let autosens = Autosens(ratio: 1, newisf: nil)
        #expect(
            DeterminationGenerator.isSMBEnabled(
                glucose: bg,
                profile: profile,
                autosens: autosens,
                mealData: mealData,
                override: nil,
                shouldProtectDueToHIGH: false,
                currentTime: now
            ) == true
        )
    }

    /// Any carb entry should enable SMB for the after-carbs window
    @Test("should enable SMB after carbs") func enableAfterCarbs() async throws {
        let now = Date()
        var profile = Profile()
        profile.enableSMBAfterCarbs = true
        let mealData = ComputedCarbs(
            carbs: 15,
            mealCOB: 0,
            currentDeviation: 0,
            maxDeviation: 0,
            minDeviation: 0,
            slopeFromMaxDeviation: 0,
            slopeFromMinDeviation: 0,
            allDeviations: [0],
            lastCarbTime: now.timeIntervalSince1970
        )
        let bg = BloodGlucose(sgv: 90, date: Decimal(now.timeIntervalSince1970 * 1000), dateString: now)
        let autosens = Autosens(ratio: 1, newisf: nil)
        #expect(
            DeterminationGenerator.isSMBEnabled(
                glucose: bg,
                profile: profile,
                autosens: autosens,
                mealData: mealData,
                override: nil,
                shouldProtectDueToHIGH: false,
                currentTime: now
            ) == true
        )
    }

    /// High-BG condition should enable SMB when above threshold
    @Test("should enable SMB for high BG") func enableWithHighBG() async throws {
        let now = Date()
        var profile = Profile()
        profile.enableSMBHighBg = true
        profile.enableSMBHighBgTarget = 130
        let bg = BloodGlucose(sgv: 135, date: Decimal(now.timeIntervalSince1970 * 1000), dateString: now)
        let autosens = Autosens(ratio: 1, newisf: nil)
        #expect(
            DeterminationGenerator.isSMBEnabled(
                glucose: bg,
                profile: profile,
                autosens: autosens,
                mealData: nil,
                override: nil,
                shouldProtectDueToHIGH: false,
                currentTime: now
            ) == true
        )
    }
}
