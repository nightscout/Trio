//
//  GarminDevice.swift
//  Trio
//
//  Created by Cengiz Deniz on 23.01.25.
//
import ConnectIQ

/// A Codable wrapper around IQDevice so we can persist it easily.
struct GarminDevice: Codable, Equatable {
    let id: UUID
    let modelName: String
    let friendlyName: String

    init(iqDevice: IQDevice) {
        id = iqDevice.uuid
        modelName = iqDevice.modelName
        friendlyName = iqDevice.modelName
    }

    var iqDevice: IQDevice {
        IQDevice(id: id, modelName: modelName, friendlyName: friendlyName)
    }
}
