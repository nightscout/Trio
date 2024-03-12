//
//  DetailedStatus+OmniKit.swift
//  OmniKit
//
//  Created by Joseph Moran on 06/22/2022
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation

// Returns an appropropriate Eros PDM style Ref string for the Detailed Status. For most Eros faults generating
// a standard style Ref code, TT-VVVHH-IIIRR-FFF is computed as {19|17}-{VV}{SSSS/60}-{NNNN/20}{RRRR/20}-PP.
extension DetailedStatus {
    public var pdmRef: String? {
        let TT: UInt8 // 11 (0x31 fault), 17 (0x14 occlusion fault) or 19 (other faults)
        let VVV: UInt8 // raw DetailedStatus VV byte (for non-occlusion faults)
        let HH: UInt8 = UInt8(timeActive.hours) // # of pod hours
        let III: UInt8 = UInt8(totalInsulinDelivered) // units of insulin
        let RR: UInt8 = UInt8(self.reservoirLevel) // reservoir units, special 50+ U value becomes 51 as needed
        let FFF: UInt8 // actual fault code value (for non-occlusion faults)

        switch faultEventCode.faultType {

        case .noFaults:
            return nil  // not a pod fault

        case .reservoirEmpty, .exceededMaximumPodLife80Hrs:
            return nil  // no Eros PDM Ref code is displayed for either of these faults

        // The Eros PDM does not display a Ref code an Auto Off 0 (the only # that the PDM uses) pod fault.
        // While Loop doesn't use this feature, extend this to all Auto Off #'s in case they ever do get used.
        case .autoOff0, .autoOff1, .autoOff2, .autoOff3, .autoOff4, .autoOff5, .autoOff6, .autoOff7:
            return nil  // no Eros PDM Ref code displayed for Auto-off pod faults

        // The Eros PDM treats the 0x31 (049) fault as a PDM error using a unique alternate TT=11 Ref code format.
        case .insulinDeliveryCommandError:
            return "11-144-0018-00049" // all fixed values for an Eros 0x31 fault

        // The Eros PDM uses VVV and FFF values of 000 in the Ref code for the 0x14 (020) occlusion fault.
        case .occluded:
            TT = 17     // Eros PDM Ref: 17-000HH-IIIRR-000
            VVV = 0     // no VVV value given for an Eros occlusion fault
            FFF = 0     // no FFF value given for an Eros occlusion fault

        // The standard Ref code displayed for all other Eros pod faults
        default:
            TT = 19     // Eros PDM Ref: 19-VVVHH-IIIRR-FFF
            VVV = data[17]
            FFF = faultEventCode.rawValue
        }

        return String(format: "%02d-%03d%02d-%03d%02d-%03d", TT, VVV, HH, III, RR, FFF)
    }
}
