//
//  SensorPairing.swift
//  LibreDirect
//
//  Created by Reimar Metzen on 06.07.21.
//
import Foundation
import Combine


public class SensorPairingInfo: ObservableObject, Codable {
    @Published public var uuid: Data
    @Published public var patchInfo: Data
    @Published public var fram: Data
    @Published public var streamingEnabled: Bool

    @Published public var sensorName : String? = nil
    
    enum CodingKeys: CodingKey {
        case uuid, patchInfo, fram, streamingEnabled, sensorName
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(uuid, forKey: .uuid)
        try container.encode(patchInfo, forKey: .patchInfo)
        try container.encode(fram, forKey: .fram)
        try container.encode(streamingEnabled, forKey: .streamingEnabled)
        try container.encode(sensorName, forKey: .sensorName)

       
    }
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        uuid = try container.decode(Data.self, forKey: .uuid)
        patchInfo = try container.decode(Data.self, forKey: .patchInfo)
        
        fram = try container.decode(Data.self, forKey: .fram)
        streamingEnabled = try container.decode(Bool.self, forKey: .streamingEnabled)
        sensorName = try container.decode(String?.self, forKey: .sensorName)
    }
    

    public init(uuid: Data=Data(), patchInfo: Data=Data(), fram: Data=Data(), streamingEnabled: Bool = false, sensorName: String? = nil ) {
        self.uuid = uuid
        self.patchInfo = patchInfo
        self.fram = fram
        self.streamingEnabled = streamingEnabled
        self.sensorName = sensorName
    }

    public var sensorData: SensorData? {
        SensorData(bytes: [UInt8](self.fram))
    }

    public var calibrationData: SensorData.CalibrationInfo? {
        sensorData?.calibrationData
    }
    
    public var description: String {
        let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted

            do {
                let data = try encoder.encode(self)  //convert user to json data here
                return String(data: data, encoding: .utf8)!   //print to console
            } catch {
                return "SensorPairingInfoError"
            }
    }

}

public protocol SensorPairingProtocol: AnyObject {
    var onCancel: (() -> Void)? { get set }
    var publisher: AnyPublisher<SensorPairingInfo, Never> { get }
    func pairSensor() throws
}
