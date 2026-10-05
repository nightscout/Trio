# Medtrum Pump BLE Simulator

Standalone macOS **training peripheral** for exercising Trio's real MedtrumKit central/driver path. It is not a medical device, does not deliver insulin, and contains no `CBCentralManager` code, so it cannot connect to or control a real pump.

## Architecture

- `MedtrumSimulatorProtocol`: radio-independent Medtrum framing, CRC-8, request reassembly, response fragmentation, protocol state, command handlers, and heartbeat encoding.
- `MedtrumPumpBLESimulator`: SwiftUI app and `CBPeripheralManager` adapter.
- CoreBluetooth publishes the real primary service and two real characteristics. The write characteristic accepts Medtrum commands and notifies responses; the read characteristic emits Medtrum state heartbeats.
- Writes are reassembled by Medtrum packet index and validated by CRC. Notifications are constrained to Medtrum's 15-byte fragment payload and queued when `updateValue` reports backpressure.
- The simulator accepts Medtrum's serial-derived authorization request but intentionally does not persist credentials. There is no OS BLE bonding requirement in the driver protocol.

## Protocol coverage

Verified against the packet encoders/parsers in this checkout's `MedtrumKit`:

- discovery and GATT UUIDs
- authorization → synchronize → subscribe connection sequence
- idle/prime/primed/activate onboarding states
- full state sync: patch state, basal, reservoir, activation time, battery, storage/patch ID, alarm flags, and age
- set/get time and set time zone
- scheduled basal profile and absolute temporary basal set/cancel
- bolus start, progress, completion, and cancel
- suspend and resume
- stop/deactivate patch
- patch settings acknowledgement
- low battery/reservoir/expiry warning flags and terminal fault-state injection

Not implemented:

- opcode 99 history-record transfer (Trio's normal sync path in this checkout does not request it)
- extended/combi bolus and relative temp basal
- CGM/auto-mode fields
- real-pump credential rejection, firmware quirks, motor timing, acoustic behavior, or physical fault recovery

The simulator therefore supports the Trio workflows listed above, but it is not a byte-for-byte model of every Medtrum firmware feature. Radio compatibility still needs an on-device iPhone test; protocol tests cannot prove macOS/iPhone RF behavior.

## macOS advertisement limitation

`CBPeripheralManager.startAdvertising(_:)` supports `CBAdvertisementDataLocalNameKey` and `CBAdvertisementDataServiceUUIDsKey` for app-supplied advertisements. It does not expose a manufacturer-data input key on macOS. The simulator therefore advertises the explicit local name `MT-SIM` and the authentic Medtrum service UUID.

The narrowly guarded MedtrumKit compatibility change recognizes only `MT-SIM` as one of two simulator identities. Real local name `MT` still requires the full eight-byte manufacturer payload, so this path cannot select a normally or malformedly advertised real pump. No Trio app files are modified.

Available identities:

- 200U training identity: enter serial `4A12D828` in Trio
- 300U training identity: enter serial `52DF1614` in Trio

## Build and test

The package requires macOS 14 or later.

```sh
cd Simulators/MedtrumPumpBLESimulator
swift build
swift test
swift run MedtrumProtocolChecks
```

Create a local signed `.app` bundle:

```sh
zsh Scripts/build-app.sh
open ".build/Medtrum Pump Simulator.app"
```

The script uses an ad-hoc hardened-runtime signature by default. For an Apple Development signature:

```sh
SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" zsh Scripts/build-app.sh
```

The app bundle includes `NSBluetoothAlwaysUsageDescription`. On first launch, allow Bluetooth access in macOS Privacy & Security.

## Pairing and training

1. Keep all real Medtrum pumps out of the training area and powered down/out of range.
2. Launch **Medtrum Pump Simulator** on a Bluetooth-capable Mac.
3. Select 200U or 300U identity, then press **Start**. Confirm `Advertising: ON`.
4. On the iPhone, open Trio's Medtrum onboarding.
5. Enter the exact serial shown by the Mac app and continue.
6. Start priming. The simulator changes from priming to primed after about three seconds.
7. Complete activation in Trio. Time sync and basal-profile activation are handled by the simulator.
8. Exercise bolus, cancel, temp basal, suspend/resume, reservoir/battery, and alarm training. Watch the protocol event log on the Mac.
9. Press **Reset** between learners. Reset restores an idle training patch. Press **Stop** to end advertising.

Do not use this software to validate dosing safety, real pump behavior, or clinical decisions.
