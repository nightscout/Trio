# Libre 2 BLE Simulator for macOS

> **TRAINING SIMULATOR — NOT A MEDICAL DEVICE**

This standalone SwiftUI Mac app is a real CoreBluetooth **peripheral**. It never
creates a `CBCentralManager`, scans for, or connects to any Libre sensor.

## Compatibility status

The app uses the stock **MiaoMiao bridge** protocol already supported by Trio:

- local name: `miaomiao` (the exact eight-byte stock identifier)
- Nordic UART service: `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`
- write characteristic: `6E400002-B5A3-F393-E0A9-E50E24DCCA9E`
- notification characteristic: `6E400003-B5A3-F393-E0A9-E50E24DCCA9E`
- stock `D3 01` sensor-confirmation and `F0` data-request handling
- 363-byte MiaoMiao responses containing a synthetic, activated 344-byte Libre
  FRAM image with valid header/body/footer CRCs, calibration, age, and
  trend/history records
- notifications split for the connected central, with
  `peripheralManagerIsReady(toUpdateSubscribers:)` flow control

There is no separate BLE alarm flag in the bridge packet parser.
Low/high scenarios therefore send low/high glucose records. Likewise, the
driver timestamps records relative to receipt time; the BLE payload carries
sensor age and record slots, not absolute timestamps.

### Why this uses the bridge path

Stock Libre 2 Direct setup requires phone NFC to activate the sensor and persist
its UID, patch info, calibration, and BLE identity before the FDE3 connection.
A BLE-only Mac cannot emulate the ISO 15693 NFC provisioning step, and stock
Trio has no manual provisioning-data import UI. macOS also cannot advertise the
arbitrary Abbott manufacturer bytes through public `CBPeripheralManager` APIs.

The stock MiaoMiao path has none of those requirements: Trio selects the bridge
by its name, then receives sensor identity, calibration, lifecycle, and glucose
inside the bridge's FRAM response. No Trio, LibreTransmitter, or Medtrum code
changes are required.

The eight-byte name is intentional. `CBPeripheralManager` can advertise only a
local name and service UUIDs; it cannot provide manufacturer data or set the
system GAP name. With the 128-bit Nordic UART UUID present, macOS can omit a
longer local name such as `miaomiao-sim`. Trio classifies `CBPeripheral.name`,
not the advertisement dictionary's local-name field, so the omitted name can
leave Trio seeing the prior `ABBOTTTRIOSIM01` identity. Stock Trio counts that
as Libre 2 Direct but hides its row in this third-party list because it requires
NFC setup. App/bundle names and Core Bluetooth restoration identifiers do not
control the remote `CBPeripheral.name`.

LibreLoop and LibreCRKit use the newer `0898...` Libre 3 services, certificate
pairing, AES data plane, and framed characteristics. Those are intentionally
not advertised because User selected Libre 2 and claiming cross-protocol
compatibility would be incorrect.

## Build and run

Requirements: macOS 14+, Bluetooth enabled, and the Apple Swift toolchain.

```sh
cd Simulators/Libre2BLESimulator
swift test --scratch-path .build/swiftpm-tests
zsh build-app.sh
open "../Apps/Libre 2 BLE Simulator.app"
```

`build-app.sh` builds Release, assembles a normal `.app`, applies an ad-hoc
code signature, verifies it, and copies it to the visible `Simulators/Apps`
directory. The Bluetooth usage strings are in `Resources/Info.plist`. On first
launch, allow Bluetooth access.

The package can also be opened directly in Xcode. Select the
`Libre2BLESimulator` executable scheme and run it on **My Mac**.

## Pair with Trio

1. Stop other apps that may be testing this synthetic identity.
2. Launch the Mac simulator and click **Start Advertising**.
3. In stock Trio, open the Libre Transmitter CGM setup, tap **Authenticate**,
   tap **Disconnect & Continue Setup**, then choose
   **Bluetooth Transmitters**. Do not choose **Libre 2 Direct**.
4. Under **Libre Transmitters**, tap the body of the **miaomiao** row once.
   The row turns pale orange and the top-right **Save** button becomes enabled.
   Tap **Save**. The “Found devices: 1” count is only a scan result; it does
   not select the row automatically.
5. Keep Trio in the foreground for the first connection. The Mac log should
   show `CENTRAL CONNECTED`, `NOTIFICATIONS SUBSCRIBED`,
   `D3 01 SENSOR CONFIRMATION RECEIVED`, and `F0 DATA REQUEST RECEIVED`,
   followed by a queued 363-byte response.
6. Choose a glucose/trend/scenario and click **Send Packet Now**, or use the
   periodic timer.

## Controls

- fixed, conspicuous training banner (always present)
- start/stop advertising and reset
- sensor serial, UID, age, warmup/ready/expired state
- target glucose and five trend rates
- sinusoidal automatic glucose curve and amplitude
- low/high glucose scenarios
- deterministic every-N-packets dropout
- packet interval and immediate send
- central subscription, MiaoMiao request status, and protocol log

## Protocol source audit

The implementation was derived from, and tested against:

- `LibreTransmitter/Bluetooth/Transmitter/MiaomiaoTransmitter.swift`
- `LibreTransmitter/Bluetooth/Transmitter/LibreTransmitterProxyManager.swift`
- `LibreTransmitter/LibreSensor/SensorContents/SensorData.swift`
- `LibreTransmitter/LibreSensor/SensorContents/CRC.swift`
- `LibreTransmitter/LibreTransmitter/LibreTransmitterManager+Transmitters.swift`

The hardware-independent test suite includes stock name classification, exact
Nordic UART UUID/capability direction, the `D3 01` then `F0` initial exchange,
stock MiaoMiao packet shape, synthetic FRAM CRC/lifecycle/age/measurement
checks, Libre 2 stream crypto test vectors retained for protocol reference,
and all trend modes.

## Limitations

- Trio identifies this as a MiaoMiao bridge, not as Libre 2 Direct. The bridge
  transports synthetic Libre-format training data through Trio's stock
  external-transmitter path.
- Direct FDE3 pairing remains impossible without first provisioning stock Trio
  through NFC; there is no manual import path.
- An ad-hoc signature is valid for local execution. Distribution to another
  Mac requires signing/notarization with your Apple Developer identity.
- CoreBluetooth peripheral mode requires compatible powered-on Mac Bluetooth
  hardware and is not exercised by unit tests.
