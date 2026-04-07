# Pod Cloud Backup & Device Transfer — Technical Specification

**Feature Name:** Pod Cloud Backup  
**Branch:** Zack-Trio  
**Author:** Zack Goettsche  
**Status:** Draft — Pre-Implementation  
**Date:** April 2026  
**Validated Against:** OmniBLE @ d8375ebf242e0d0e02ace7a03d9e1632557de38e (loopandlearn/OmniBLE, branch trio)

---

## Table of Contents

1. [Overview & Motivation](#1-overview--motivation)
2. [The Problem in Detail](#2-the-problem-in-detail)
3. [Why Security Is Critical](#3-why-security-is-critical)
4. [Technical Background: How Pod-Device Binding Works](#4-technical-background-how-pod-device-binding-works)
5. [Data That Must Be Backed Up](#5-data-that-must-be-backed-up)
6. [Architecture Decision: Firebase](#6-architecture-decision-firebase)
7. [Security Architecture](#7-security-architecture)
8. [Firestore Data Model](#8-firestore-data-model)
9. [Sync Strategy](#9-sync-strategy)
10. [Device Locking & Conflict Prevention](#10-device-locking--conflict-prevention)
11. [Recovery Flow (New Phone)](#11-recovery-flow-new-phone)
12. [BLE Re-Discovery](#12-ble-re-discovery)
13. [Firebase Project Setup (Per-User)](#13-firebase-project-setup-per-user)
14. [Relationship to Existing Firebase Integrations](#14-relationship-to-existing-firebase-integrations)
15. [Phased Implementation Plan](#15-phased-implementation-plan)
16. [Open Questions & Risk Register](#16-open-questions--risk-register)

---

## 1. Overview & Motivation

Trio users running Omnipod Dash pods are critically dependent on a single iPhone. If that phone is lost, destroyed, or becomes unusable — especially while traveling — the user has no way to resume closed-loop insulin delivery on a replacement device. The pod itself is still active and viable, but all of the cryptographic pairing state that allows communication with the pod lives only on the original phone's local storage.

This feature adds **automatic, continuous, encrypted cloud backup** of all pod communication state and Trio therapy settings to a user-owned Firebase project. On a replacement device, the user can restore everything needed to resume communication with an active pod — without needing access to the old phone at all.

This is a **personal safety feature** for a medical device. That framing must guide every design and implementation decision.

---

## 2. The Problem in Detail

### What currently happens when a phone is lost mid-pod

1. User installs Trio on a new phone via TestFlight.
2. Trio has no knowledge of the currently active pod.
3. There is no way to pair an already-activated pod with a new device — Trio will attempt a fresh pair, which requires a new pod.
4. The active pod, which may have 40–60 hours of life remaining, must be discarded.
5. In a travel scenario (abroad, no supply), the user may have no spare pod available.
6. The user falls back to manual injection until a replacement pod is obtained.

### Why a QR code export approach doesn't solve it

An obvious first approach is to have the user export pod state as a QR code or file whenever they switch phones. This fails the disaster scenario entirely: if the phone is wet, smashed, or stolen, it cannot present a QR code. The state must already be in the cloud **before** the disaster occurs.

---

## 3. Why Security Is Critical

The data being backed up is not merely a settings file. It includes the **Long Term Key (LTK)** — a 16-byte `Data` value negotiated during pod pairing using X25519 Diffie-Hellman key exchange (CryptoKit `Curve25519.KeyAgreement`). Possession of the LTK, combined with the pod address and current session counters, is sufficient to:

- Establish a new authenticated session with the physical Omnipod Dash pod
- Send arbitrary commands to the pod via BLE, including bolus, basal rate changes, and suspend

This means a compromised LTK is equivalent to **physical access to someone's insulin pump**. The consequences of an attacker gaining unauthorized control of a pod range from hypoglycemia to a life-threatening insulin overdose.

**Security requirements that follow from this:**

- The LTK and all associated pod state must **never be stored in plaintext** in any cloud service, including the user's own Firebase project
- Firebase admins, Anthropic, and the developer of this feature must never be able to read the LTK
- The encryption key must be derived exclusively from a secret known only to the user (their passphrase), and that passphrase must never leave the device
- Authentication to the backup service must be multi-factor
- Old pod data must be automatically purged after pod expiry

---

## 4. Technical Background: How Pod-Device Binding Works

### 4.1 Application-Level Pairing (Not OS-Level Bonding)

The Omnipod Dash does **not** use iOS CoreBluetooth bonding or iOS-managed BLE security. Instead, all cryptographic binding is done at the application layer:

1. **Initial pairing:** X25519 Diffie-Hellman key exchange via `LTKExchanger.swift` using CryptoKit `Curve25519.KeyAgreement`. The result is the LTK — a 16-byte `Data` value stored in `PodState.ltk: Data`.
2. **Per-session key derivation:** Each communication session derives ephemeral keys (`ck`, `noncePrefix`) from the LTK using the Milenage algorithm via `SessionEstablisher.swift`.
3. **Message encryption:** All BLE messages are encrypted with AES-CCM using the per-session keys.

Because the binding is entirely in software state (not iOS Secure Enclave hardware), it is fully portable — it can be serialized, stored, and restored on a different device.

### 4.2 The bleIdentifier Problem

CoreBluetooth assigns each peripheral a UUID that is unique per iOS device. The same physical Omnipod Dash pod gets a **different UUID on every iPhone**. This means `PodState.bleIdentifier` cannot be transferred directly — it is meaningless on the new device.

The solution is BLE re-discovery: on the new device, scan for nearby Dash pods and match by pod address (from the backup). Critically, the pod address (`podId`), `lotNo`, and lot sequence number are **encoded in the BLE advertisement data itself** (parsed from the service UUID array in `PodAdvertisement.swift`) — no preliminary connection or handshake is needed before matching. Once the correct peripheral is found, update `bleIdentifier` and proceed with session establishment.

### 4.3 PodState Serialization

`PodState` already conforms to `RawRepresentable` with a `[String: Any]` dictionary. `MessageTransportState` has its own `RawRepresentable` conformance and is nested inside `PodState.rawValue` under the key `"messageTransportState"`. `OmniBLEPumpManagerState` wraps `PodState?` (note: optional) and is also fully serializable.

The backup feature reuses this serialization pathway — the same `rawValue` dictionary that gets written to disk locally also gets encrypted and uploaded to Firestore.

### 4.4 Session Re-Establishment

Session establishment signature (from `PodComms.swift:236`):

```swift
private func establishSession(ltk: Data, eapSeq: Int, msgSeq: Int = 1) throws -> MessageTransportState?
```

Only the LTK (`Data`) and the current EAP sequence number are required to negotiate fresh session keys with the pod. `msgSeq` defaults to 1. The new device can establish its own session using the transferred LTK without any coordination with the old device — as long as the old device is not simultaneously active (see Section 10).

Note: `establishSession` is `private` — session re-establishment on the new device must go through the same internal `PodComms` pathway used during normal operation, not called directly from the backup restoration code.

---

## 5. Data That Must Be Backed Up

There are two distinct backup payloads.

### 5.1 Pod State Payload

This is the critical safety payload. It must be synced **after every pod command**.

The primary strategy is to serialize the entire `OmniBLEPumpManagerState.rawValue` dictionary as JSON. This is robust against future OmniBLE changes. The table below documents what is inside that payload and why each field matters — it is also the validation checklist for Phase 1 unit tests.

**Fields on `PodState`** (`OmniBLE/OmniBLE/PumpManager/PodState.swift`):

| Property Name | Type | rawValue Key | Why It's Needed |
|---|---|---|---|
| `ltk` | `Data` | `"ltk"` (hex string) | Master secret; required to establish any new session |
| `address` | `UInt32` | `"address"` | Pod address for BLE targeting and re-discovery matching |
| `bleIdentifier` | `String?` | `"bleIdentifier"` | Stored but replaced during re-discovery on new device |
| `activatedAt` | `Date?` | `"activatedAt"` | Pod start time; needed for expiry calculation |
| `expiresAt` | `Date?` | `"expiresAt"` | Pod expiry; used for Firestore TTL and UI |
| `lotNo` | `UInt32` | `"lotNo"` | Lot number; used for re-discovery advertisement matching |
| `lotSeq` | `UInt32` | `"lotSeq"` | Lot sequence number; additional re-discovery matching criterion |
| `productId` | `UInt8` | `"productId"` | Pod product type |
| `insulinType` | `InsulinType` | `"insulinType"` | Needed for correct dose calculations |
| `suspendState` | `SuspendState` | `"suspendState"` | Is the pod currently suspended? |
| `lastInsulinMeasurements` | `PodInsulinMeasurements?` | `"lastInsulinMeasurements"` | Contains `reservoirLevel: Double?` — last known reservoir reading |
| `unfinalizedBolus` | `UnfinalizedDose?` | `"unfinalizedBolus"` | In-flight bolus not yet confirmed |
| `unfinalizedTempBasal` | `UnfinalizedDose?` | `"unfinalizedTempBasal"` | In-flight temp basal not yet confirmed |
| `unfinalizedSuspend` | `UnfinalizedDose?` | `"unfinalizedSuspend"` | In-flight suspend not yet confirmed |
| `unfinalizedResume` | `UnfinalizedDose?` | `"unfinalizedResume"` | In-flight resume not yet confirmed |
| `finalizedDoses` | `[UnfinalizedDose]` | `"finalizedDoses"` | Completed doses pending upload |
| `configuredAlerts` | `[AlertSlot: PodAlert]` | `"configuredAlerts"` | Alerts currently configured on pod |
| `activeAlertSlots` | `AlertSet` | `"activeAlertSlots"` | Currently firing alerts |
| `setupProgress` | `SetupProgress` | `"setupProgress"` | Is the pod fully activated? |
| `firmwareVersion` | `FirmwareVersion` | `"firmwareVersion"` | Pod firmware; protocol compatibility |
| `bleFirmwareVersion` | `FirmwareVersion` | `"bleFirmwareVersion"` | BLE chip firmware version |
| `podTime` | `TimeInterval` | `"podTime"` | Time elapsed on pod clock |
| `podTimeUpdated` | `Date?` | `"podTimeUpdated"` | When pod time was last read |
| `activeTime` | `TimeInterval?` | `"activeTime"` | Total active time |
| `fault` | `DetailedStatus?` | `"fault"` | Pod fault state if any |
| `unacknowledgedCommand` | `PendingCommand?` | `"unacknowledgedCommand"` | Command awaiting acknowledgment |
| `messageTransportState` | `MessageTransportState` | `"messageTransportState"` | Full session counter state (see below) |

**Fields on `MessageTransportState`** (nested in `PodState.rawValue["messageTransportState"]`):

| Property Name | Type | rawValue Key | Why It's Needed |
|---|---|---|---|
| `eapSeq` | `Int` | `"eapSeq"` | EAP sequence number; must be current to negotiate session |
| `msgSeq` | `Int` | `"msgSeq"` | Message packet sequence number |
| `nonceSeq` | `Int` | `"nonceSeq"` | Nonce counter; must not repeat |
| `messageNumber` | `Int` | `"messageNumber"` | Omnipod command sequence |
| `ck` | `Data` | `"ck"` | Current session cipher key (ephemeral) |
| `noncePrefix` | `Data` | `"noncePrefix"` | Current nonce prefix (ephemeral) |

**Additional top-level fields on `OmniBLEPumpManagerState`** (`OmniBLE/OmniBLE/PumpManager/OmniBLEPumpManagerState.swift`):

| Field | Notes |
|---|---|
| `basalSchedule` | Moved off `PodState` in state version 2; lives here |
| `insulinType` | Top-level copy; also on PodState |
| `isOnboarded` | Pump onboarding state |
| `timeZone` | Timezone for scheduled dosing |
| `unstoredDoses` | Doses pending upload to HealthKit/Nightscout |
| `silencePod` | User preference |
| `confirmationBeeps` | User preference |
| `controllerId` / `podId` | Controller and pod identity |
| `scheduledExpirationReminderOffset` | Alert timing preference |
| `defaultExpirationReminderOffset` | Alert timing preference |
| `lowReservoirReminderValue` | Alert threshold |
| `podAttachmentConfirmed` | Setup state |
| `activeAlerts` / `alertsWithPendingAcknowledgment` | Alert tracking |
| `acknowledgedTimeOffsetAlert` | Alert state |
| `lastPumpDataReportDate` | Last successful data report |
| `previousPodState` | Previous pod for dose continuity |
| `initialConfigurationCompleted` | Setup state |
| `maximumTempBasalRate` | Safety limit |

All of the above are captured by serializing `OmniBLEPumpManagerState.rawValue`. No manual field extraction is needed.

### 5.2 Therapy Settings Payload

Therapy settings are stored as **JSON files** via `BaseFileStorage` (file-based, not Core Data). The central type is `TherapyProfile` containing basal profile, insulin sensitivities, carb ratios, and BG targets. Pump settings are in `PumpSettings`. Settings are managed by `ProfileManager`.

File paths follow the pattern `settings/basal_profile.json`, `settings/insulin_sensitivities.json`, etc.

This payload is synced on settings changes. It is not safety-critical in the same way as pod state but is operationally important — manually re-entering all settings on a new device in an emergency is error-prone.

| Data | Source Type | File Path |
|---|---|---|
| Basal profile | `TherapyProfile.basalProfile` | `settings/basal_profile.json` |
| Insulin Sensitivity Factor | `TherapyProfile.insulinSensitivities` | `settings/insulin_sensitivities.json` |
| Carb Ratio | `TherapyProfile.carbRatios` | `settings/carb_ratios.json` |
| BG targets | `TherapyProfile.bgTargets` | `settings/bg_targets.json` |
| Pump settings | `PumpSettings` | `settings/settings.json` |
| Max bolus / max basal | `PumpSettings` | `settings/settings.json` |
| Dynamic ISF / SMB / algorithm | `FreeAPSSettings` | `settings/preferences.json` |

---

## 6. Architecture Decision: Firebase

### 6.1 Why Firebase over iCloud CloudKit

Both Firebase and iCloud CloudKit are technically viable. The decision is Firebase. Rationale:

- Full control over the authentication model — email/password + MFA is straightforward
- Client-side encryption can be layered on independently. CloudKit end-to-end encrypted fields are harder to control at the app level
- The LTK commands an insulin pump. Trusting a single provider (Apple) with implicit key management is insufficient defense-in-depth
- The developer is already familiar with Firebase
- Firebase already has two other integrations in this codebase (see Section 14)
- Free tier (Spark plan) handles this data volume easily — two tiny JSON documents per user, updated dozens of times per day

### 6.2 Per-User Firebase Projects

Each user sets up their own Firebase project. This is a deliberate design choice:

- No single entity (including the developer) has access to any user's backup data
- No shared infrastructure cost or maintenance burden
- No multi-tenancy security risks
- Consistent with the DIY ethos of the Trio project

The tradeoff is setup friction, mitigated by step-by-step in-app guidance (see Phase 2).

---

## 7. Security Architecture

### 7.1 Three-Layer Defense

**Layer 1 — Firebase Authentication (email/password + email MFA)**

Proves the person accessing the backup is the account owner. Firebase Auth supports email/password with email-based MFA. Both will be supported; email MFA is recommended as the lower-friction option.

**Layer 2 — Client-Side AES-256-GCM Encryption (passphrase-derived key)**

The backup payload is encrypted on-device before it is ever sent to Firebase. Firebase never receives the plaintext LTK.

Key derivation:
- User sets a memorable recovery passphrase during setup
- Derive a 256-bit encryption key using PBKDF2-SHA256 with 600,000 iterations (OWASP 2023 recommendation) and a random 32-byte salt via CommonCrypto
- The salt is stored alongside the encrypted blob in Firestore (not secret — prevents rainbow table attacks)
- The passphrase never leaves the device and is never stored in Firebase
- Encryption via CryptoKit `AES.GCM` (AES-256-GCM provides authenticated encryption — integrity protection is built in)

On recovery: user enters passphrase on new device, same PBKDF2 derivation with stored salt, blob decrypts.

**Note on Argon2:** Argon2 is preferable in theory (memory-hard) but requires a third-party Swift package unavailable in CryptoKit or CommonCrypto. PBKDF2-SHA256 at 600k iterations is the native choice and acceptable here.

**Layer 3 — Automatic Expiry**

Pod state data is automatically deleted from Firestore after pod expiry (72-hour nominal life + 8-hour buffer = 80 hours from `activatedAt`). Firestore TTL is configured on the `podExpiry` field of each document.

### 7.2 Firestore Security Rules

```javascript
// Only authenticated users can read/write their own documents
match /users/{userId}/{document=**} {
  allow read, write: if request.auth != null && request.auth.uid == userId;
}
```

Step-by-step rule setup is included in the in-app setup wizard.

### 7.3 What a Breach Reveals

If an attacker compromises the Firestore database contents: they obtain the encrypted blob, IV, and salt — but cannot decrypt without the passphrase. PBKDF2 at 600k iterations makes brute force of a strong passphrase computationally expensive.

Even with the decrypted LTK, the attacker must be physically within Bluetooth range (~10 meters) of the pod. Active pod sessions enforce sequence numbers — out-of-sequence messages are rejected.

Users should understand the passphrase must be kept as secure as an insulin pump access code.

---

## 8. Firestore Data Model

Three documents per user, under their Firebase Auth UID.

### 8.1 Pod State Document

**Path:** `/users/{uid}/podBackup/current`

```json
{
  "encryptedPayload": "<base64-encoded AES-256-GCM ciphertext>",
  "iv": "<base64-encoded 12-byte GCM nonce>",
  "salt": "<base64-encoded 32-byte PBKDF2 salt>",
  "kdfIterations": 600000,
  "schemaVersion": 1,
  "timestamp": "<Firestore server timestamp>",
  "podExpiry": "<Firestore timestamp — used for TTL auto-deletion>",
  "deviceId": "<UUID identifying the currently active/writing device>",
  "appVersion": "<Trio build version string>"
}
```

The `encryptedPayload` decrypts to the JSON-encoded `OmniBLEPumpManagerState.rawValue` dictionary.

### 8.2 Settings Document

**Path:** `/users/{uid}/settingsBackup/current`

```json
{
  "encryptedPayload": "<base64-encoded AES-256-GCM ciphertext>",
  "iv": "<base64-encoded 12-byte GCM nonce>",
  "salt": "<base64-encoded 32-byte PBKDF2 salt>",
  "kdfIterations": 600000,
  "schemaVersion": 1,
  "timestamp": "<Firestore server timestamp>",
  "appVersion": "<Trio build version string>"
}
```

The `encryptedPayload` decrypts to a JSON object containing the serialized contents of the settings JSON files listed in Section 5.2.

### 8.3 Device Lock Document

**Path:** `/users/{uid}/deviceLock/current`

```json
{
  "activeDeviceId": "<UUID of the device currently authorized to control the pod>",
  "acquiredAt": "<Firestore server timestamp>",
  "lastHeartbeat": "<Firestore server timestamp — updated every 5 minutes by active device>"
}
```

See Section 10 for device lock semantics.

---

## 9. Sync Strategy

### 9.1 Pod State Sync Triggers

Pod state sync is triggered after **every successful pod command**:

- After bolus delivery (standard, extended, or correction)
- After temp basal set/cancel
- After suspend/resume
- After pod status poll (getStatus)
- After alert acknowledgment
- Immediately after pod pairing (first sync, includes initial LTK)

### 9.2 Offline Handling

1. After each successful pod command, attempt Firestore write
2. If the write fails (no connectivity), enqueue the current state locally (UserDefaults key with timestamp)
3. On next app foreground or network restoration, flush the queue
4. If multiple commands occurred while offline, only the most recent state needs uploading — intermediate states are superseded
5. Never block pod commands waiting for Firestore — sync is always fire-and-forget from the command execution path

The backup may lag by however long the device was offline. This is acceptable.

### 9.3 Settings Sync Triggers

- User saves any settings change in Trio
- App launches (catch any missed syncs)
- User explicitly taps "Sync Now" in backup settings screen

---

## 10. Device Locking & Conflict Prevention

Two devices sending commands to the same pod with out-of-sync sequence numbers will cause communication failures and potentially corrupt pod command state. Only one device may hold the active device lock.

### 10.1 Lock Acquisition

When a new device restores from backup:

1. Read `deviceLock/current`
2. If `lastHeartbeat` is older than 10 minutes, the old device is presumed dead — take the lock
3. Write new device's ID to `deviceLock/current`
4. Old device, upon next app foreground, reads the lock and sees it no longer holds it

### 10.2 Lock Lost — Old Device Behavior

When an old device detects it has lost the lock:

1. On app foreground, read `deviceLock/current`
2. If `activeDeviceId` != own device ID, present a blocking alert: *"This device is no longer the active controller for your pod. Pod control has moved to another device. This device will not send any pod commands."*
3. Disable all pod command pathways on the old device

### 10.3 Lock Heartbeat

The active device writes to `lastHeartbeat` every 5 minutes. A recovering device uses staleness > 10 minutes to distinguish a dead old device from a still-active one.

### 10.4 Intentional Device Transfer

In a non-emergency planned switch:

1. Old device: Settings → Pod Backup → "Transfer to New Device"
2. Old device writes `activeDeviceId: nil` and disables itself
3. New device picks up the unlocked state and claims the lock

---

## 11. Recovery Flow (New Phone)

### 11.1 Step-by-Step Recovery

```
1.  Install Trio via TestFlight on new phone
2.  Launch Trio
3.  On welcome/onboarding screen: tap "Restore from Cloud Backup"
4.  Enter Firebase email address
5.  Enter Firebase password
6.  Complete MFA (email code)
7.  Enter recovery passphrase
    → App derives encryption key via PBKDF2, decrypts OmniBLEPumpManagerState from Firestore
    → Displays summary: "Found backup from [timestamp]. Pod expires [time]. 
      Therapy settings included."
8.  Tap "Restore"
    → OmniBLEPumpManagerState reconstructed from decrypted payload
    → Therapy settings JSON files written to local storage via FileStorage
    → App acquires device lock in Firestore
9.  App scans for nearby Dash pod via BLE
    → BluetoothManager.discoverPods() / startScanning() reused
    → Match by podId, lotNo, lotSeq from advertisement data
    → No connection needed before matching
10. bleIdentifier updated to new device's CoreBluetooth UUID for matched peripheral
11. Session established via PodComms using recovered ltk + eapSeq + msgSeq
12. Pod status read to confirm connection
13. ✅ Looping resumes
```

### 11.2 Failure Cases

| Failure | User-Facing Message | Resolution |
|---|---|---|
| No internet on new phone | "Cannot connect to backup service. Connect to WiFi or cellular and try again." | Retry |
| Wrong passphrase | "Incorrect passphrase. Check your passphrase and try again." | Retry (no lockout — passphrase never sent to server) |
| No backup found | "No backup found for this account." | Check email address, or proceed with fresh setup |
| Pod expired | "The backed-up pod has expired. You will need to start a new pod." | Proceed with fresh pod pairing |
| Pod not found nearby | "Could not find your pod nearby. Make sure you are within Bluetooth range (~10 meters) and try again." | Retry scan |
| Session establishment fails | "Could not reconnect to pod. The pod may need to be deactivated." | Manual escalation |

---

## 12. BLE Re-Discovery

### 12.1 The Problem

`PodState.bleIdentifier` is a CoreBluetooth peripheral UUID assigned per iOS device. It is useless on a new phone.

### 12.2 The Solution

1. Start CoreBluetooth scan using `BluetoothManager.startScanning()` (reuse existing code)
2. For each discovered peripheral, parse `PodAdvertisement` from advertisement data
3. The advertisement encodes `podId` (pod address), `lotNo`, and `lotSeq` in the service UUID array — readable **without connecting**
4. Compare against `PodState.address`, `PodState.lotNo`, `PodState.lotSeq` from backup
5. On match: update `bleIdentifier` to new device's UUID for that peripheral
6. Proceed with `PodComms` session establishment using recovered `ltk`, `eapSeq`, `msgSeq`

**BLE Service UUID:** `00004024-0000-1000-8000-00805f9b34fb`

### 12.3 Proximity Requirement

User must be within Bluetooth range (~10 meters) of the pod. Make this explicit in the UI before starting the scan.

### 12.4 Multiple Pods Nearby

The three-field match (`podId` + `lotNo` + `lotSeq`) uniquely identifies the correct pod even in clinical settings with multiple Dash users.

---

## 13. Firebase Project Setup (Per-User)

### 13.1 What the User Creates

1. A Firebase project (free tier, requires Google account)
2. Firestore Database enabled
3. Firebase Authentication enabled, email/password provider enabled
4. MFA configured on their Firebase Auth account
5. A user account in Firebase Auth (email + password)
6. Firestore security rules configured (provided verbatim by app)
7. Firebase project configuration values entered into Trio

### 13.2 Configuration Stored in Trio

Copied from Firebase console by the user:

- Firebase API Key
- Firebase Auth Domain
- Firebase Project ID
- Firebase App ID

These are public project identifiers, not secrets. Stored in iOS Keychain (not UserDefaults). They are **not** backed up to Firebase (circular dependency — user must re-enter them on a new device, but this is quick).

---

## 14. Relationship to Existing Firebase Integrations

Trio (Zack-Trio branch) currently has two Firebase integrations:

**Integration 1 — Crashlytics**
- Default Firebase app, initialized via standard `GoogleService-Info.plist`
- Used for crash reporting only (no Firebase Analytics)
- Source: `Trio/Sources/Application/AppDelegate.swift`

**Integration 2 — Garmin Health Data (SmartSense)**
- Secondary Firebase app instance
- Used for Garmin health data relay (sleep, stress, HRV, body battery) to power SmartSense features
- Credentials injected at build time via `GarminFirebaseConstants` (placeholder strings replaced during build — not user-provided)
- Source: `Trio/Sources/Services/Garmin/GarminFirebaseConfig.swift`, `GarminFirestoreService.swift`

**Integration 3 — Pod Cloud Backup (this feature)**
- Third Firebase app instance
- User's own Firebase project — credentials entered by user at runtime, stored in Keychain
- Completely independent of the other two integrations; no shared project resources

This follows the multi-app Firebase pattern already established in the codebase.

---

## 15. Phased Implementation Plan

### Phase 1 — Foundation & Core Encryption (No UI)

**Goal:** Prove the core technical loop end-to-end in unit tests: serialize pod state → encrypt → store → retrieve → decrypt → restore.

**Tasks:**
- [ ] Create `PodCloudBackupService.swift`
- [ ] Implement PBKDF2-SHA256 key derivation (CommonCrypto, 600k iterations)
- [ ] Implement AES-256-GCM encrypt/decrypt (CryptoKit `AES.GCM`)
- [ ] Implement Firestore document write for pod state payload
- [ ] Implement Firestore document read for pod state payload
- [ ] Unit test: encrypt/decrypt round-trip produces identical data
- [ ] Unit test: `OmniBLEPumpManagerState.rawValue` → JSON → parse → reconstruct with no field loss
- [ ] Unit test: verify all fields from Section 5.1 tables survive round-trip (pay special attention to `Data` fields serialized as hex, `Date` fields, nested `MessageTransportState`)

**Success criteria:** A test that takes a real `OmniBLEPumpManagerState`, serializes it, encrypts it, decrypts it, and reconstructs an identical state with no data loss.

---

### Phase 2 — Firebase Auth & Setup Flow

**Goal:** Users can create and configure their Firebase project and link it to Trio.

**Tasks:**
- [ ] Add third Firebase app initialization path using user-provided runtime credentials
- [ ] Build "Enable Pod Backup" settings screen
  - Firebase API Key / Auth Domain / Project ID / App ID entry
  - Firebase email + password sign-in
  - MFA setup / verification
  - Recovery passphrase entry and confirmation (with strength guidance)
  - Passphrase stored only in iOS Keychain, never uploaded
- [ ] Display Firestore security rules template for user to copy to Firebase console
- [ ] Setup validation: test write → test read → confirm success
- [ ] Store all Firebase config values in Keychain

---

### Phase 3 — Continuous Sync

**Goal:** Pod state is automatically kept current in Firestore after every pod command.

**Tasks:**
- [ ] Identify all pod command completion points in `OmniBLEPumpManager` and `PodComms`
- [ ] Hook sync trigger at each point (post-command, on success only)
- [ ] Implement offline queue (UserDefaults-backed, flush on network restore / app foreground)
- [ ] Implement settings sync (on settings save, on app launch)
- [ ] Add sync status indicator: "Last synced: 2 minutes ago"
- [ ] Add non-blocking sync error banner when sync has been failing > 30 minutes
- [ ] Implement device heartbeat (5-minute interval → `deviceLock.lastHeartbeat`)

---

### Phase 4 — Device Lock

**Goal:** Prevent two devices from commanding the same pod simultaneously.

**Tasks:**
- [ ] Generate persistent device UUID per app install (Keychain)
- [ ] Implement lock acquisition on first sync
- [ ] Implement lock check on app foreground
- [ ] Implement lock-lost detection → disable pod command pathways
- [ ] Implement "Transfer to New Device" intentional handoff
- [ ] Implement stale lock override (heartbeat > 10 minutes)

---

### Phase 5 — Recovery Flow

**Goal:** Full end-to-end recovery on a new phone including BLE re-discovery.

**Tasks:**
- [ ] Add "Restore from Cloud Backup" to Trio onboarding screen
- [ ] Build recovery UI: email → password → MFA → passphrase → preview → restore
- [ ] Implement Firestore read + decrypt on new device
- [ ] Reconstruct `OmniBLEPumpManagerState` from decrypted payload
- [ ] Write therapy settings JSON files to local storage via `FileStorage`
- [ ] Implement BLE re-discovery using `BluetoothManager.startScanning()` + `PodAdvertisement` matching on `podId` / `lotNo` / `lotSeq`
- [ ] Update `bleIdentifier` after re-discovery
- [ ] Session establishment via `PodComms` using recovered `ltk`, `eapSeq`, `msgSeq`
- [ ] Handle all failure cases from Section 11.2
- [ ] **End-to-end test on two physical iPhones with a real pod**

---

### Phase 6 — Polish & Safety Hardening

**Tasks:**
- [ ] Configure Firestore TTL on `podExpiry` field (auto-delete 80 hours post-activation)
- [ ] Schema version migration path for future changes
- [ ] Recovery passphrase change flow (re-encrypt + re-upload with new key)
- [ ] "Delete My Backup" option
- [ ] Backup health dashboard: last sync time, pod expiry, device lock status
- [ ] Security review of encryption implementation
- [ ] User documentation: setup guide, recovery guide, passphrase management
- [ ] TestFlight beta with small group of experienced users before wider rollout

---

## 16. Open Questions & Risk Register

| # | Question / Risk | Severity | Resolution |
|---|---|---|---|
| 1 | What happens if `eapSeq` / `msgSeq` is stale at recovery — old phone sent commands after last backup? | High | Pod rejects session with out-of-sequence error. Need to characterize the pod's tolerance window for counter skew. Session retry with incremented counters may recover. Must test on real hardware. |
| 2 | `establishSession` is `private` — how does recovery code invoke it? | High | Recovery must trigger session establishment through the same `PodComms` internal pathway used during normal pairing/reconnection. Identify the correct public entry point (likely through `OmniBLEPumpManager.connect()` or equivalent). |
| 3 | PBKDF2 at 600k iterations: is it fast enough on older iPhones for good UX? | Medium | Benchmark on iPhone 11 (oldest likely device). Expect ~1–2 seconds. If unacceptable, reduce iterations with documented tradeoff, or move derivation to background thread with loading indicator. |
| 4 | Firebase free tier: 20k Firestore writes/day. Will sync stay within limits? | Low | ~50–100 writes/day typical. 20k/day gives 200x headroom. Throttle to max 1 write per 30 seconds if needed. |
| 5 | User loses passphrase — no recovery path by design. | High | Cannot be worked around — we cannot store the passphrase. Document clearly and prominently. Encourage password manager storage. Provide a passphrase rotation flow so users can change it proactively. |
| 6 | User loses Firebase email/password credentials. | Medium | Standard Firebase password reset via email. MFA recovery codes must be saved. Document in setup flow. |
| 7 | Two physical phones online simultaneously attempt to sync conflicting state. | High | Device lock (Section 10) prevents this. Last-write-wins acceptable only if lock is correctly enforced. |
| 8 | Pod firmware update changes advertisement format, breaking re-discovery. | Low | `PodAdvertisement.swift` parsing is the single point to update. Abstract re-discovery matching behind an interface for easy future updates. |
| 9 | `OmniBLEPumpManagerState.podState` is optional (`PodState?`). Recovery with nil podState. | Medium | If `podState` is nil in the backup, there is no pod to recover. Detect this in the preview step (Step 7 of recovery flow) and inform the user no active pod backup exists. |

---

*This document is a pre-implementation specification. It describes intent and design, not completed code. All implementation decisions are subject to revision as development proceeds. Validated against OmniBLE commit d8375ebf, November 2025.*
