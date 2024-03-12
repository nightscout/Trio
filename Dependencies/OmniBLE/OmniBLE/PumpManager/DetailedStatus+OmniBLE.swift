//
//  DetailedStatus+OmniBLE.swift
//  OmniBLE
//
//  Created by Joseph Moran on 01/07/2022
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation

// Returns an appropropriate DASH PDM style Ref string for DetailedStatus. DASH Ref codes are all of
// the form Ref: TT-VVVHH-IIIRR-FFF computed as {14|15|16|17|19}-{VV}{SSSS/60}-{NNNN/20}{RRRR/20}-PP.
extension DetailedStatus {
    public var pdmRef: String? {
        let TT: UInt8 // 14 (0x18 empty), 15 (0x29 auto-off), 16 (0x1C >80 hr), 17 (0x14 occlusion) or 19 (other)
        let VVV: UInt8 = data[17] // raw DetailedStatus VV byte
        let HH: UInt8 = UInt8(timeActive.hours) // # of pod hours
        let III: UInt8 = UInt8(totalInsulinDelivered) // units of insulin
        let RR: UInt8 = UInt8(self.reservoirLevel) // reservoir units, special 50+ U value becomes 51 as needed
        let FFF: UInt8 = faultEventCode.rawValue // actual fault code value

        switch faultEventCode.faultType {

        case .noFaults:
            return nil  // not a pod fault

        // The DASH PDM defines the AlarmHazardPumpFailure type (TT=11), but
        // doesn't use it for anything including the 0x31 (-049) pod fault!

        // The DASH PDM uses the AlarmHazardPumpVolume type (TT=14) for the 0x18 (024) pod fault.
        case .reservoirEmpty:
            TT = 14     // DASH PDM Ref: 14-VVVHH-IIIRR-024

        // The DASH PDM uses the AlarmHazardPumpAutoOff type (TT=15) for a 0x29 (041) autoOff0 pod fault
        // (the only autoOff# it actually uses). While Loop doesn't use the Auto Off feature for anything,
        // map all autoOff# pod faults to AlarmHazardPumpAutoOff in case these ever do get used for something.
        case .autoOff0, .autoOff1, .autoOff2, .autoOff3, .autoOff4, .autoOff5, .autoOff6, .autoOff7:
            TT = 15     // DASH PDM Ref: 15-VVVHH-IIIRR-FFF

        // The DASH PDM uses the AlarmHazardPumpExpired type (TT=16) for the 0x1C (028) pod fault.
        case .exceededMaximumPodLife80Hrs:
            TT = 16     // DASH PDM Ref: 16-VVVHH-IIIRR-028

        // The DASH PDM uses the AlarmHazardPumpOcclusion type (TT=17) for an 0x14 (-020) occlusion fault.
        // Unlike the Eros PDM, the DASH PDM doesn't do anything special with the other values for this Ref code.
        case .occluded:
            TT = 17     // DASH PDM Ref: 17-VVVHH-IIIRR-020

        // The DASH PDM defines the AlarmHazardPumpActivate type (TT=18) and the
        // AlarmHazardPumpCommunications type (TT=20), but doesn't actually use either!

        // The DASH PDM uses the AlarmHazardPumpError type (TT=19) for all other pod faults.
        default:
            TT = 19     // DASH PDM Ref: 19-VVVHH-IIIRR-FFF
        }

        return String(format: "%02d-%03d%02d-%03d%02d-%03d", TT, VVV, HH, III, RR, FFF)
    }
}
