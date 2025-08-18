func parseMessage(data: Data, usingUtc: Bool) -> (any DanaParsePacketProtocol)? {
    let receivedCommand = (UInt16(data[TypeIndex] & 0xFF) << 8) + UInt16(data[OpCodeIndex] & 0xFF)

    guard let parser = findMessageParser[receivedCommand] else {
        return nil
    }

    var parsedResult = parser(data, usingUtc) as! (any DanaParsePacketProtocol)
    parsedResult.command = receivedCommand
    parsedResult.opCode = data[OpCodeIndex] & 0xFF

    return parsedResult
}

let findMessageParser: [UInt16: (Data, Bool?) -> Any] = [
    CommandBasalCancelTemporary: parsePacketBasalCancelTemporary,
    CommandBasalGetProfileNumber: parsePacketBasalGetProfileNumber,
    CommandBasalGetRate: parsePacketBasalGetRate,
    CommandBasalSetProfileRate: parsePacketBasalSetProfileRate,
    CommandBasalSetProfileNumber: parsePacketBasalSetProfileNumber,
    CommandBasalSetSuspendOff: parsePacketBasalSetSuspendOff,
    CommandBasalSetSuspendOn: parsePacketBasalSetSuspendOn,
    CommandBasalSetTemporary: parsePacketBasalSetTemporary,
    CommandBolusCancelExtended: parsePacketBolusCancelExtended,
    CommandBolusGet24CIRCFArray: parsePacketBolusGet24CIRCFArray,
    CommandBolusGetCIRCFArray: parsePacketBolusGetCIRCFArray,
    CommandBolusGetCalculationInformation: parsePacketBolusGetCalculationInformation,
    CommandBolusGetOption: parsePacketBolusGetOption,
    CommandBolusGetStepInformation: parsePacketBolusGetStepInformation,
    CommandBolusSet24CIRCFArray: parsePacketBolusSet24CIRCFArray,
    CommandBolusSetExtended: parsePacketBolusSetExtended,
    CommandBolusSetOption: parsePacketBolusSetOption,
    CommandBolusStart: parsePacketBolusStart,
    CommandBolusStop: parsePacketBolusStop,
    CommandGeneralAvgBolus: parsePacketGeneralAvgBolus,
    CommandGeneralClearUserTimeChangeFlag: parsePacketGeneralClearUserTimeChangeFlag,
    CommandGeneralGetInitialScreenInformation: parsePacketGeneralGetInitialScreenInformation,
    CommandGeneralGetPumpCheck: parsePacketGeneralGetPumpCheck,
    CommandGeneralGetPumpDecRatio: parsePacketGeneralGetPumpDecRatio,
    CommandGeneralGetPumpTime: parsePacketGeneralGetPumpTime,
    CommandGeneralGetPumpTimeUtcWithTimezone: parsePacketGeneralGetPumpTimeUtcWithTimezone,
    CommandGeneralGetShippingInformation: parsePacketGeneralGetShippingInformation,
    CommandGeneralGetShippingVersion: parsePacketGeneralGetShippingVersion,
    CommandGeneralGetUserOption: parsePacketGeneralGetUserOption,
    CommandGeneralGetUserTimeChangeFlag: parsePacketGeneralGetUserTimeChangeFlag,
    CommandGeneralKeepConnection: parsePacketGeneralKeepConnection,
    CommandGeneralSaveHistory: parsePacketGeneralSaveHistory,
    CommandGeneralSetHistoryUploadMode: parsePacketGeneralSetHistoryUploadMode,
    CommandGeneralSetPumpTime: parsePacketGeneralSetPumpTime,
    CommandGeneralSetPumpTimeUtcWithTimezone: parsePacketGeneralSetPumpTimeUtcWithTimezone,
    CommandGeneralSetUserOption: parsePacketGeneralSetUserOption,
    CommandHistoryAlarm: parsePacketHistory,
    CommandHistoryAll: parsePacketHistory,
    CommandHistoryBasal: parsePacketHistory,
    CommandHistoryBloodGlucose: parsePacketHistory,
    CommandHistoryBolus: parsePacketHistory,
    CommandHistoryCarbohydrates: parsePacketHistory,
    CommandHistoryDaily: parsePacketHistory,
    CommandHistoryPrime: parsePacketHistory,
    CommandHistoryRefill: parsePacketHistory,
    CommandHistorySuspend: parsePacketHistory,
    CommandHistoryTemporary: parsePacketHistory,
    CommandLoopHistoryEvents: parsePacketLoopHistoryEvents,
    CommandLoopSetEventHistory: parsePacketLoopSetEventHistory,
    CommandLoopSetTemporaryBasal: parsePacketLoopSetTemporaryBasal,
    CommandNotifyAlarm: parsePacketNotifyAlarm,
    CommandNotifyDeliveryComplete: parsePacketNotifyDeliveryComplete,
    CommandNotifyDeliveryRateDisplay: parsePacketNotifyDeliveryRateDisplay,
    CommandNotifyMissedBolus: parsePacketNotifyMissedBolus
]
