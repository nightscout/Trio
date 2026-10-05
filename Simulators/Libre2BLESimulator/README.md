# Libre 2 BLE Simulator for macOS

> **TRAINING SIMULATOR — NOT A MEDICAL DEVICE**

This standalone SwiftUI Mac app is a real CoreBluetooth **peripheral**. It never
creates a `CBCentralManager`, scans for, or connects to any Libre sensor.

## Compatibility status

The app implements the protocol used by this repository's selected **Libre 2
direct** driver:

- advertisement service: `FDE3`
- local name: `ABBOTTTRIOSIM01`
- primary GATT service: `FDE3`
- unlock write characteristic: `F001` (`write` with response)
- encrypted notification characteristic: `F002`
- the repository's 12-byte streaming-unlock calculation and validation
- the repository's Libre 2 stream cipher, 46-byte encrypted packets, 44-byte
  plaintext, CRC-16, ten packed trend/history records, and sensor-age field
- notifications split as 20 + 20 + 6 bytes, with
  `peripheralManagerIsReady(toUpdateSubscribers:)` flow control

There is no separate BLE alarm flag in the direct driver's packet parser.
Low/high scenarios therefore send low/high glucose records. Likewise, the
driver timestamps records relative to receipt time; the BLE payload carries
sensor age and record slots, not absolute timestamps.

### Why stock Trio cannot initially pair

This is not a missing cryptographic implementation. Trio's Libre 2 setup first
uses phone NFC to activate a physical sensor, read UID/patch/calibration data,
and obtain its BLE name/MAC. The simulator cannot emulate an ISO 15693 NFC tag.
Also, macOS `CBPeripheralManager` accepts local-name and service-UUID
advertisement keys but does not expose manufacturer-data advertising. Stock
Trio's first-discovery path requires NFC-provisioned identity plus either the
real eight-byte manufacturer field or the NFC-returned name/MAC.

`Compatibility/Trio-Libre2-training-provisioning.patch` adds one DEBUG-only
button that installs a fixed synthetic UID, patch info, calibration, and local
name. Release behavior is unchanged. The simulator then works through the
existing real Libre 2 driver without changing its UUIDs, crypto, parser, or BLE
transport. The patch is supplied but is **not applied** by this directory.

LibreLoop and LibreCRKit use the newer `0898...` Libre 3 services, certificate
pairing, AES data plane, and framed characteristics. Those are intentionally
not advertised because User selected Libre 2 and claiming cross-protocol
compatibility would be incorrect.

## Build and run

Requirements: macOS 14+, Bluetooth enabled, and the Apple Swift toolchain.

```sh
cd Simulators/Libre2BLESimulator
swift test
zsh build-app.sh
open ".build/Libre 2 BLE Simulator.app"
```

`build-app.sh` builds Release, assembles a normal `.app`, applies an ad-hoc
code signature, and verifies it. The Bluetooth usage strings are in
`Resources/Info.plist`. On first launch, allow Bluetooth access.

The package can also be opened directly in Xcode. Select the
`Libre2BLESimulator` executable scheme and run it on **My Mac**.

## Pair with Trio

1. Stop other apps that may be testing this synthetic identity.
2. Apply the compatibility patch from the repository root:

   ```sh
   git apply --check Simulators/Libre2BLESimulator/Compatibility/Trio-Libre2-training-provisioning.patch
   git apply Simulators/Libre2BLESimulator/Compatibility/Trio-Libre2-training-provisioning.patch
   ```

3. Build and install Trio with the **Debug** configuration. The button is
   compiled out of Release builds.
4. Launch the Mac simulator and click **Start Advertising**.
5. In Trio, add/select Libre 2 and tap **Use Libre 2 Training Simulator**.
6. Keep Trio in the foreground for initial discovery. It should discover
   `ABBOTTTRIOSIM01`, connect to FDE3, subscribe to F002, and write the normal
   F001 unlock. The Mac log shows each stage.
7. Choose a glucose/trend/scenario and click **Send Packet Now**, or use the
   periodic timer.

To remove the temporary driver change:

```sh
git apply -R Simulators/Libre2BLESimulator/Compatibility/Trio-Libre2-training-provisioning.patch
```

Do not apply or reverse the patch over unrelated edits to the same setup file;
use normal source control conflict review in that case.

## Controls

- fixed, conspicuous training banner (always present)
- start/stop advertising and reset
- sensor serial, UID, age, warmup/ready/expired state
- target glucose and five trend rates
- sinusoidal automatic glucose curve and amplitude
- low/high glucose scenarios
- deterministic every-N-packets dropout
- packet interval and immediate send
- central subscription, unlock status, and protocol log

## Protocol source audit

The implementation was derived from, and tested against:

- `LibreTransmitter/Bluetooth/Transmitter/Libre2DirectTransmitter.swift`
- `LibreTransmitter/Bluetooth/Transmitter/LibreTransmitterProxyManager.swift`
- `LibreTransmitter/LibreSensor/SensorContents/PreLibre2.swift`
- `LibreTransmitter/LibreSensor/SensorContents/CRC.swift`
- `LibreTransmitter/LibreSensor/SensorPairing/SensorPairingService.swift`
- `LibreTransmitter/LibreTransmitter/LibreTransmitterManager+Libre2EU.swift`
- `LibreCRKit/Sources/LibreCRKit/BLE/LibreSensorGATT.swift`
- `LibreCRKit/Sources/LibreCRKit/Pairing/PairingFlow.swift`
- `LibreLoop/LibreLoop/Pairing/LibreLoopPairingService.swift`

The hardware-independent test suite includes the encrypted packet captured in
`Libre2.Example.BLEExample`, round-trip crypto, CRC, age/record encoding, unlock
validation, and all trend modes.

## Limitations

- The optional DEBUG provisioning path is required for first pairing; NFC
  activation itself cannot be simulated by a BLE-only Mac app.
- macOS cannot provide the Libre 2 manufacturer advertisement bytes through
  public `CBPeripheralManager` APIs. Name/MAC matching is used by the repository
  driver's existing 2025+ path.
- An ad-hoc signature is valid for local execution. Distribution to another
  Mac requires signing/notarization with your Apple Developer identity.
- CoreBluetooth peripheral mode requires compatible powered-on Mac Bluetooth
  hardware and is not exercised by unit tests.
