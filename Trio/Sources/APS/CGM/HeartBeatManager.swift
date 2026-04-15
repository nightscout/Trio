import Foundation

class HeartBeatManager {
    private let keyForcgmTransmitterDeviceAddress = "cgmTransmitterDeviceAddress"

    private let keyForcgmTransmitter_CBUUID_Service = "cgmTransmitter_CBUUID_Service"

    private let keycgmTransmitter_CBUUID_Receive = "cgmTransmitter_CBUUID_Receive"

    /// to be used as singleton, no instanstation from outside allowed - class to be accessed via shared
    static let shared = HeartBeatManager()

    /// - instance of bluetoothTransmitter that will connect to the CGM, with goal to achieve heartbeat mechanism,  nothing else
    /// - if nil then there's no heartbeat generated
    private var bluetoothTransmitter: BluetoothTransmitter?

    private var initialSetupDone = false

    /// to be used as singleton, no instanstation from outside allowed
    private init() {}

    /// verifies if local copy of cgmTransmitterDeviceAddress  is different than the one stored in shared User Defaults
    /// - parameters:
    ///     - sharedData : shared User Defaults
    public func checkCGMBluetoothTransmitter(sharedUserDefaults: UserDefaults, heartbeat: DispatchTimer?) {
        if !initialSetupDone {
            initialSetupDone = true

            // set to nil, this will force recreation of bluetooth transmitter at app startup
            UserDefaults.standard.cgmTransmitterDeviceAddress = nil
        }

        if UserDefaults.standard.cgmTransmitterDeviceAddress != sharedUserDefaults
            .string(forKey: keyForcgmTransmitterDeviceAddress)
        {
            // assign local copy of cgmTransmitterDeviceAddress to the value stored in sharedUserDefaults (possibly nil value)
            UserDefaults.standard.cgmTransmitterDeviceAddress = sharedUserDefaults
                .string(forKey: keyForcgmTransmitterDeviceAddress)

            // assign new bluetoothTransmitter. If return value is nil, and if it was not nil before, and if it was currently connected then it will disconnect automatically, because there's no other reference to it, hence deinit will be called
            bluetoothTransmitter = setupBluetoothTransmitter(sharedData: sharedUserDefaults, heartbeat: heartbeat)
        }
    }

    private func setupBluetoothTransmitter(sharedData: UserDefaults, heartbeat: DispatchTimer?) -> BluetoothTransmitter? {
        // if sharedUserDefaults.cgmTransmitterDeviceAddress is not nil then, create a new bluetoothTranmsitter instance
        if let cgmTransmitterDeviceAddress = sharedData.string(forKey: keyForcgmTransmitterDeviceAddress) {
            // unwrap cgmTransmitter_CBUUID_Service and cgmTransmitter_CBUUID_Receive
            if let cgmTransmitter_CBUUID_Service = sharedData.string(forKey: keyForcgmTransmitter_CBUUID_Service),
               let cgmTransmitter_CBUUID_Receive = sharedData.string(forKey: keycgmTransmitter_CBUUID_Receive)
            {
                // a new cgm transmitter has been setup in xDrip4iOS
                // we will connect to the same transmitter here so it can be used as heartbeat
                let newBluetoothTransmitter = BluetoothTransmitter(
                    deviceAddress: cgmTransmitterDeviceAddress,
                    servicesCBUUID: cgmTransmitter_CBUUID_Service,
                    CBUUID_Receive: cgmTransmitter_CBUUID_Receive,
                    heartbeat: {
                        if let heartbeatAvailable = heartbeat {
                            heartbeatAvailable.fire()
                        }
                    }
                )

                return newBluetoothTransmitter

            } else {
                // looks like a coding error, xdrip4iOS did set a value for cgmTransmitterDeviceAddress in sharedUserDefaults but did not set a value for cgmTransmitter_CBUUID_Service or cgmTransmitter_CBUUID_Receive

                return nil
            }
        }

        return nil
    }
}
