//
//  FaultEventCode.swift
//  OmniKit
//
//  Created by Pete Schwamb on 9/28/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation


public struct FaultEventCode: CustomStringConvertible, Equatable {
    public let rawValue: UInt8
    
    public enum FaultEventType: UInt8 {
        case noFaults                             = 0x00
        case failedFlashErase                     = 0x01
        case failedFlashStore                     = 0x02
        case tableCorruptionBasalSubcommand       = 0x03
        case basalPulseTableCorruption            = 0x04
        case corruptionByte720                    = 0x05
        case dataCorruptionInTestRTCInterrupt     = 0x06
        case rtcInterruptHandlerInconsistentState = 0x07
        case valueGreaterThan8                    = 0x08
        case invalidBeepRepeatPattern             = 0x09
        case bf0notEqualToBF1                     = 0x0A
        case tableCorruptionTempBasalSubcommand   = 0x0B

        case resetDueToCOP                        = 0x0D
        case resetDueToIllegalOpcode              = 0x0E
        case resetDueToIllegalAddress             = 0x0F
        case resetDueToSAWCOP                     = 0x10
        case corruptionInByte_866                 = 0x11
        case resetDueToLVD                        = 0x12
        case messageLengthTooLong                 = 0x13
        case occluded                             = 0x14
        case corruptionInWord129                  = 0x15
        case corruptionInByte868                  = 0x16
        case corruptionInAValidatedTable          = 0x17
        case reservoirEmpty                       = 0x18
        case badPowerSwitchArrayValue1            = 0x19
        case badPowerSwitchArrayValue2            = 0x1A
        case badLoadCnthValue                     = 0x1B
        case exceededMaximumPodLife80Hrs          = 0x1C
        case badStateCommand1AScheduleParse       = 0x1D
        case unexpectedStateInRegisterUponReset   = 0x1E
        case wrongSummaryForTable129              = 0x1F
        case validateCountErrorWhenBolusing       = 0x20
        case badTimerVariableState                = 0x21
        case unexpectedRTCModuleValueDuringReset  = 0x22
        case problemCalibrateTimer                = 0x23
        case tickcntErrorRTC                      = 0x24
        case tickFailure                          = 0x25
        case rtcInterruptHandlerUnexpectedCall    = 0x26
        case missing2hourAlertToFillTank          = 0x27
        case faultEventSetupPod                   = 0x28
        case autoOff0                             = 0x29
        case autoOff1                             = 0x2A
        case autoOff2                             = 0x2B
        case autoOff3                             = 0x2C
        case autoOff4                             = 0x2D
        case autoOff5                             = 0x2E
        case autoOff6                             = 0x2F
        case autoOff7                             = 0x30
        case insulinDeliveryCommandError          = 0x31
        case badValueStartupTest                  = 0x32
        case connectedPodCommandTimeout           = 0x33
        case resetFromUnknownCause                = 0x34
        case vetoNotSet                           = 0x35
        case errorFlashInitialization             = 0x36
        case badPiezoValue                        = 0x37
        case unexpectedValueByte358               = 0x38
        case problemWithLoad1and2                 = 0x39
        case aGreaterThan7inMessage               = 0x3A
        case failedTestSawReset                   = 0x3B
        case testInProgress                       = 0x3C
        case problemWithPumpAnchor                = 0x3D
        case errorFlashWrite                      = 0x3E

        case encoderCountTooHigh                  = 0x40
        case encoderCountExcessiveVariance        = 0x41
        case encoderCountTooLow                   = 0x42
        case encoderCountProblem                  = 0x43
        case checkVoltageOpenWire1                = 0x44
        case checkVoltageOpenWire2                = 0x45
        case problemWithLoad1and2type46           = 0x46
        case problemWithLoad1and2type47           = 0x47
        case badTimerCalibration                  = 0x48
        case badTimerRatios                       = 0x49
        case badTimerValues                       = 0x4A
        case trimICSTooCloseTo0x1FF               = 0x4B
        case problemFindingBestTrimValue          = 0x4C
        case badSetTPM1MultiCasesValue            = 0x4D
        case sawTrimError                         = 0x4E
        case unexpectedRFErrorFlagDuringReset     = 0x4F
        case timerPulseWidthModulatorOverflow     = 0x50
        case tickcntError                         = 0x51
        case badRfmXtalStart                      = 0x52
        case badRxSensitivity                     = 0x53
        case packetFrameLengthTooLong             = 0x54
        case unexpectedIRQHighinTimerTick         = 0x55
        case unexpectedIRQLowinTimerTick          = 0x56
        case badArgToGetEntry                     = 0x57
        case badArgToUpdate37ATable               = 0x58
        case errorUpdating37ATable                = 0x59
        case occlusionCheckValueTooHigh           = 0x5A
        case loadTableCorruption                  = 0x5B
        case primeOpenCountTooLow                 = 0x5C
        case badValueByte109                      = 0x5D
        case disableFlashSecurityFailed           = 0x5E
        case checkVoltageFailure                  = 0x5F
        case occlusionCheckStartup1               = 0x60
        case occlusionCheckStartup2               = 0x61
        case occlusionCheckTimeouts1              = 0x62

        case occlusionCheckTimeouts2              = 0x66
        case occlusionCheckTimeouts3              = 0x67
        case occlusionCheckPulseIssue             = 0x68
        case occlusionCheckBolusProblem           = 0x69
        case occlusionCheckAboveThreshold         = 0x6A

        case basalUnderInfusion                   = 0x80
        case basalOverInfusion                    = 0x81
        case tempBasalUnderInfusion               = 0x82
        case tempBasalOverInfusion                = 0x83
        case bolusUnderInfusion                   = 0x84
        case bolusOverInfusion                    = 0x85
        case basalOverInfusionPulse               = 0x86
        case tempBasalOverInfusionPulse           = 0x87
        case bolusOverInfusionPulse               = 0x88
        case immediateBolusOverInfusionPulse      = 0x89
        case extendedBolusOverInfusionPulse       = 0x8A
        case corruptionOfTables                   = 0x8B
        case unrecognizedPulse                    = 0x8D
        case syncWithoutTempActive                = 0x8E
        case command1AParseUnexpectedFailed       = 0x8F
        case illegalChanParam                     = 0x90
        case basalPulseChanInactive               = 0x91
        case tempPulseChanInactive                = 0x92
        case bolusPulseChanInactive               = 0x93
        case intSemaphoreNotSet                   = 0x94
        case illegalInterLockChan                 = 0x95
        case badStateInClearBolusIST2AndVars      = 0x96
        case badStateInMaybeInc33D                = 0x97
        case valuesDoNotMatch                     = 0xFF
    }

    public var faultType: FaultEventType? {
        return FaultEventType(rawValue: rawValue)
    }
    
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public var faultDescription: String {
        switch faultType {
        case .noFaults:
            return "No fault"
        case .failedFlashErase:
            return "Flash erase failed"
        case .failedFlashStore:
            return "Flash store failed"
        case .tableCorruptionBasalSubcommand:
            return "Basal subcommand table corruption"
        case .basalPulseTableCorruption:
            return "Basal pulse table corruption"
        case .corruptionByte720:
            return "Corruption in byte_720"
        case .dataCorruptionInTestRTCInterrupt:
            return "Data corruption error in test_RTC_interrupt"
        case .rtcInterruptHandlerInconsistentState:
            return "RTC interrupt handler called with inconstent state"
        case .valueGreaterThan8:
            return "Value > 8"
        case .invalidBeepRepeatPattern:
            return "Invalid beep repeat pattern"
        case .bf0notEqualToBF1:
            return "Corruption in byte_BF0"
        case .tableCorruptionTempBasalSubcommand:
            return "Temp basal subcommand table corruption"
        case .resetDueToCOP:
            return "Reset due to COP"
        case .resetDueToIllegalOpcode:
            return "Reset due to illegal opcode"
        case .resetDueToIllegalAddress:
            return "Reset due to illegal address"
        case .resetDueToSAWCOP:
            return "Reset due to SAWCOP"
        case .corruptionInByte_866:
            return "Corruption in byte_866"
        case .resetDueToLVD:
            return "Reset due to LVD"
        case .messageLengthTooLong:
            return "Message length too long"
        case .occluded:
            return "Occluded"
        case .corruptionInWord129:
            return "Corruption in word_129 table/word_86A/dword_86E"
        case .corruptionInByte868:
            return "Corruption in byte_868"
        case .corruptionInAValidatedTable:
            return "Corruption in a validated table"
        case .reservoirEmpty:
            return "Reservoir empty or exceeded maximum pulse delivery"
        case .badPowerSwitchArrayValue1:
            return "Bad Power Switch Array Status and Control Register value 1 before starting pump"
        case .badPowerSwitchArrayValue2:
            return "Bad Power Switch Array Status and Control Register value 2 before starting pump"
        case .badLoadCnthValue:
            return "Bad LOADCNTH value when running pump"
        case .exceededMaximumPodLife80Hrs:
            return "Exceeded maximum Pod life of 80 hours"
        case .badStateCommand1AScheduleParse:
            return "Unexpected internal state in command_1A_schedule_parse_routine_wrapper"
        case .unexpectedStateInRegisterUponReset:
            return "Unexpected commissioned state in status and control register upon reset"
        case .wrongSummaryForTable129:
            return "Sum mismatch for word_129 table"
        case .validateCountErrorWhenBolusing:
            return "Validate encoder count error when bolusing"
        case .badTimerVariableState:
            return "Bad timer variable state"
        case .unexpectedRTCModuleValueDuringReset:
            return "Unexpected RTC Modulo Register value during reset"
        case .problemCalibrateTimer:
            return "Problem in calibrate_timer_case_3"
        case .tickcntErrorRTC:
            return "Tick count error RTC"
        case .tickFailure:
            return "Tick failure"
        case .rtcInterruptHandlerUnexpectedCall:
            return "RTC interrupt handler unexpectedly called"
        case .missing2hourAlertToFillTank:
            return "Failed to set up 2 hour alert for tank fill operation"
        case .faultEventSetupPod:
            return "Bad arg or state in update_insulin_variables, verify_and_start_pump or main_loop_control_pump"
        case .autoOff0:
            return "Alert #0 auto-off timeout"
        case .autoOff1:
            return "Alert #1 auto-off timeout"
        case .autoOff2:
            return "Alert #2 auto-off timeout"
        case .autoOff3:
            return "Alert #3 auto-off timeout"
        case .autoOff4:
            return "Alert #4 auto-off timeout"
        case .autoOff5:
            return "Alert #5 auto-off timeout"
        case .autoOff6:
            return "Alert #6 auto-off timeout"
        case .autoOff7:
            return "Alert #7 auto-off timeout"
        case .insulinDeliveryCommandError:
            return "Incorrect pod state for command or error during insulin command setup"
        case .badValueStartupTest:
            return "Bad value during startup testing"
        case .connectedPodCommandTimeout:
            return "Connected Pod command timeout"
        case .resetFromUnknownCause:
            return "Reset from unknown cause"
        case .vetoNotSet:
            return "Veto not set"
        case .errorFlashInitialization:
            return "Flash initialization error"
        case .badPiezoValue:
            return "Bad piezo value"
        case .unexpectedValueByte358:
            return "Unexpected byte_358 value"
        case .problemWithLoad1and2:
            return "Problem with LOAD1/LOAD2"
        case .aGreaterThan7inMessage:
            return "A > 7 in message processing"
        case .failedTestSawReset:
            return "SAW reset testing fail"
        case .testInProgress:
            return "test in progress"
        case .problemWithPumpAnchor:
            return "Problem with pump anchor"
        case .errorFlashWrite:
            return "Flash initialization or write error"
        case .encoderCountTooHigh:
            return "Encoder count too high"
        case .encoderCountExcessiveVariance:
            return "Encoder count excessive variance"
        case .encoderCountTooLow:
            return "Encoder count too low"
        case .encoderCountProblem:
            return "Encoder count problem"
        case .checkVoltageOpenWire1:
            return "Check voltage open wire 1 problem"
        case .checkVoltageOpenWire2:
            return "Check voltage open wire 2 problem"
        case .problemWithLoad1and2type46:
            return "Problem with LOAD1/LOAD2"
        case .problemWithLoad1and2type47:
            return "Problem with LOAD1/LOAD2"
        case .badTimerCalibration:
            return "Bad timer calibration"
        case .badTimerRatios:
            return "Bad timer values: COP timer ratio bad"
        case .badTimerValues:
            return "Bad timer values"
        case .trimICSTooCloseTo0x1FF:
            return "ICS trim too close to 0x1FF"
        case .problemFindingBestTrimValue:
            return "find_best_trim_value problem"
        case .badSetTPM1MultiCasesValue:
            return "Bad set_TPM1_multi_cases value"
        case .unexpectedRFErrorFlagDuringReset:
            return "Unexpected TXSCR2 RF Tranmission Error Flag set during reset"
        case .timerPulseWidthModulatorOverflow:
            return "Timer pulse-width modulator overflow"
        case .tickcntError:
            return "Bad tick count state before starting pump"
        case .badRfmXtalStart:
            return "TXOK issue in process_input_buffer"
        case .badRxSensitivity:
            return "Bad Rx word_107 sensitivity value during input message processing"
        case .packetFrameLengthTooLong:
            return "Packet frame length too long"
        case .unexpectedIRQHighinTimerTick:
            return "Unexpected IRQ high in timer_tick"
        case .unexpectedIRQLowinTimerTick:
            return "Unexpected IRQ low in timer_tick"
        case .badArgToGetEntry:
            return "Corrupt constants table at byte_37A[] or flash byte_4036[]"
        case .badArgToUpdate37ATable:
            return "Bad argument to update_37A_table"
        case .errorUpdating37ATable:
            return "Error updating constants byte_37A table"
        case .occlusionCheckValueTooHigh:
            return "Occlusion check value too high for detection"
        case .loadTableCorruption:
            return "Load table corruption"
        case .primeOpenCountTooLow:
            return "Prime open count too low"
        case .badValueByte109:
            return "Bad byte_109 value"
        case .disableFlashSecurityFailed:
            return "Write flash byte to disable flash security failed"
        case .checkVoltageFailure:
            return "Two check voltage failures before starting pump"
        case .occlusionCheckStartup1:
            return "Occlusion check startup problem 1"
        case .occlusionCheckStartup2:
            return "Occlusion check startup problem 2"
        case .occlusionCheckTimeouts1:
            return "Occlusion check excess timeouts 1"
        case .occlusionCheckTimeouts2:
            return "Occlusion check excess timeouts 2"
        case .occlusionCheckTimeouts3:
            return "Occlusion check excess timeouts 3"
        case .occlusionCheckPulseIssue:
            return "Occlusion check pulse issue"
        case .occlusionCheckBolusProblem:
            return "Occlusion check bolus problem"
        case .occlusionCheckAboveThreshold:
            return "Occlusion check above threshold"
        case .basalUnderInfusion:
            return "Basal under infusion"
        case .basalOverInfusion:
            return "Basal over infusion"
        case .tempBasalUnderInfusion:
            return "Temp basal under infusion"
        case .tempBasalOverInfusion:
            return "Temp basal over infusion"
        case .bolusUnderInfusion:
            return "Bolus under infusion"
        case .bolusOverInfusion:
            return "Bolus over infusion"
        case .basalOverInfusionPulse:
            return "Basal over infusion pulse"
        case .tempBasalOverInfusionPulse:
            return "Temp basal over infusion pulse"
        case .bolusOverInfusionPulse:
            return "Bolus over infusion pulse"
        case .immediateBolusOverInfusionPulse:
            return "Immediate bolus under infusion pulse"
        case .extendedBolusOverInfusionPulse:
            return "Extended bolus over infusion pulse"
        case .corruptionOfTables:
            return "Corruption of $283/$2E3/$315 tables"
        case .unrecognizedPulse:
            return "Bad pulse value to verify_and_start_pump"
        case .syncWithoutTempActive:
            return "Pump sync req 5 with no temp basal active"
        case .command1AParseUnexpectedFailed:
            return "Command 1A parse routine unexpected failed"
        case .illegalChanParam:
            return "Bad parameter for $283/$2E3/$315 channel table specification"
        case .basalPulseChanInactive:
            return "Pump basal request with basal IST not set"
        case .tempPulseChanInactive:
            return "Pump temp basal request with temp basal IST not set"
        case .bolusPulseChanInactive:
            return "Pump bolus request and bolus IST not set"
        case .intSemaphoreNotSet:
            return "Bad table specifier field6 in 1A command"
        case .illegalInterLockChan:
            return "Illegal interlock channel"
        case .badStateInClearBolusIST2AndVars:
            return "Bad variable state in clear_Bolus_IST2_and_vars"
        case .badStateInMaybeInc33D:
            return "Bad variable state in maybe_inc_33D"
        default:
            return "Unknown fault code"
        }
    }

    public var description: String {
        return String(format: "Fault Event Code 0x%02x: %@", rawValue, faultDescription)
    }
    
    public var localizedDescription: String {
        if let faultType = faultType {
            switch faultType {
            case .noFaults:
                return LocalizedString("No faults", comment: "Description for Fault Event Code .noFaults")
            case .reservoirEmpty:
                return LocalizedString("Empty reservoir", comment: "Description for Empty reservoir pod fault")
            case .exceededMaximumPodLife80Hrs:
                return LocalizedString("Pod expired", comment: "Description for Pod expired pod fault")
            case .occluded:
                return LocalizedString("Occlusion detected", comment: "Description for Occlusion detected pod fault")
            default:
                return String(format: LocalizedString("Internal pod fault %1$03d", comment: "The format string for Internal pod fault (1: The fault code value)"), rawValue)
            }
        } else {
            return String(format: LocalizedString("Unknown pod fault %1$03d", comment: "The format string for Unknown pod fault (1: The fault code value)"), rawValue)
        }
    }
}
