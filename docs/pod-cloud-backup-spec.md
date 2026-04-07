# Pod Cloud Backup & Device Transfer — Technical Specification

**Feature Name:** Pod Cloud Backup  
**Branch:** Zack-Trio  
**Author:** Zack Goettsche  
**Status:** Draft — Pre-Implementation  
**Date:** April 2026

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

The data being backed up is not merely a settings file. It includes the **Long Term Key (LTK)** — a 16-byte cryptographic secret negotiated during pod pairing using X25519 Diffie-Hellman key exchange. Possession of the LTK, combined with the pod address and current session counters, is sufficient to:

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

Understanding the OmniBLE architecture is essential to understanding what must be transferred and why.

### 4.1 Application-Level Pairing (Not OS-Level Bonding)

The Omnipod Dash does **not** use iOS CoreBluetooth bonding or iOS-managed BLE security. Instead, all cryptographic binding is done at the application layer using a custom EAP-AKA-like protocol:

1. **Initial pairing:** X25519 Diffie-Hellman key exchange via `LTKExchanger.swift`. The result is the LTK — a 16-byte shared secret stored in `PodState.ltk`.
2. **Per-session key derivation:** Each communication session derives ephemeral keys (`ck`, `noncePrefix`) from the LTK using a 3GPP Milenage-derived function in `PodComms.swift`.
3. **Message encryption:** All BLE messages are encrypted with AES-CCM using the session keys.

Because the binding is entirely in software state (not iOS Secure Enclave hardware), it is fully portable — it can be serialized, stored, and restored on a different device.

### 4.2 The bleIdentifier Problem

CoreBluetooth assigns each peripheral a UUID that is unique per iOS device. The same physical Omnipod Dash pod gets a **different UUID on every iPhone**. This means `PodState.bleIdentifier` cannot be transferred directly — it is meaningless on the new device.

The solution is BLE re-discovery: on the new device, scan for nearby Dash pods and match by pod address (from the backup). Once the correct peripheral is found, update `bleIdentifier` to the new device's UUID and proceed with session establishment.

### 4.3 PodState Serialization

`PodState` already conforms to `RawRepresentable` with a `[String: Any]` dictionary. All crypto fields are serialized as hex strings. `OmniBLEPumpManagerState` wraps `PodState` and is also fully serializable. This is the existing persistence mechanism used for local plist storage.

The backup feature reuses this serialization pathway — the same `rawValue` dictionary that gets written to disk locally also gets encrypted and uploaded to Firestore.

### 4.4 Session Re-Establishment

When a new session is established (`PodComms.establishSession(ltk:eapSeq:msgSeq:)`), only the LTK and the current EAP sequence number are required to negotiate fresh session keys with the pod. The new device can establish its own session using the transferred LTK without any coordination with the old device — as long as the old device is not simultaneously active (see Section 10).

---

## 5. Data That Must Be Backed Up

There are two distinct backup payloads.

### 5.1 Pod State Payload

This is the critical safety payload. It must be synced **after every pod command**.

| Field | Source | Why It's Needed |
|---|---|---|
| `ltk` | `PodState.ltk` (hex string) | Master secret; required to establish any new session |
| `address` | `PodState.address` (UInt32) | Used to address the pod over BLE; used for re-discovery matching |
| `eapSeq` | `MessageTransportState.eapSeq` | EAP sequence number; must be current to negotiate session |
| `msgSeq` | `MessageTransportState.msgSeq` | Message packet sequence number |
| `nonceSeq` | `MessageTransportState.nonceSeq` | Nonce counter; must not repeat |
| `messageNumber` | `MessageTransportState.messageNumber` | Omnipod command sequence |
| `ck` | `MessageTransportState.ck` | Current session cipher key (ephemeral, regenerated on session start) |
| `noncePrefix` | `MessageTransportState.noncePrefix` | Current nonce prefix (ephemeral, regenerated on session start) |
| `activatedAt` | `PodState.activatedAt` | Pod start time; needed for expiry calculation |
| `expiresAt` | `PodState.expiresAt` | Pod expiry; used for Firestore TTL and UI |
| `lot` | `PodState.lot` | Used for re-discovery confirmation and pod identity |
| `tid` | `PodState.tid` | Pod serial number; used for re-discovery confirmation |
| `insulinType` | `PodState.insulinType` | Needed for correct dose calculations |
| `suspendState` | `PodState.suspendState` | Is the pod currently suspended? |
| `reservoirLevel` | Last known reservoir reading | UI and safety |
| `basalSchedule` | `PodState.basalSchedule` | Currently programmed basal |
| `unfinalizedDoses` | `PodState.unfinalizedDoses` | In-flight doses that haven't been confirmed |
| `configuredAlerts` | `PodState.configuredAlerts` | Alerts currently set on the pod |
| `setupProgress` | `PodState.setupProgress` | Is the pod fully activated? |
| `firmwareVersion` | `PodState.firmwareVersion` | Pod firmware; used for protocol compatibility |
| Full `OmniBLEPumpManagerState.rawValue` | Entire manager state | Catch-all: captures any fields not listed individually |

**Implementation note:** Rather than selectively extracting individual fields, serialize the entire `OmniBLEPumpManagerState.rawValue` dictionary as JSON. This is more robust against future OmniBLE changes and ensures no field is accidentally omitted.

### 5.2 Therapy Settings Payload

This payload is synced on settings changes. It is not safety-critical in the same way as the pod state but is operationally important — manually re-entering all settings on a new device in an emergency is error-prone.

| Data | Source |
|---|---|
| Basal profile(s) | `FreeAPSSettings` / Core Data |
| Insulin Sensitivity Factor (ISF) schedule | `FreeAPSSettings` |
| Carb Ratio (CR) schedule | `FreeAPSSettings` |
| Correction targets (glucose targets) | `FreeAPSSettings` |
| Max bolus / max basal rate | `FreeAPSSettings` |
| Dynamic ISF settings | `FreeAPSSettings` |
| Autotune settings | `FreeAPSSettings` |
| SMB settings | `FreeAPSSettings` |
| Notification preferences | `FreeAPSSettings` |
| Pump model / configuration | `OmniBLEPumpManagerState` |

---

## 6. Architecture Decision: Firebase

### 6.1 Why Firebase over iCloud CloudKit

Both Firebase and iCloud CloudKit are technically viable for this use case. The decision is Firebase. Rationale:

**Firebase advantages:**
- Full control over the authentication model — email/password + email MFA is straightforward
- Client-side encryption can be layered on top without any framework constraints. CloudKit end-to-end encrypted fields are harder to control at the app level
- The LTK is the key to commanding an insulin pump. Trusting a single provider (Apple) with implicit key management is insufficient defense-in-depth
- The developer (Zack) is already familiar with Firebase
- Firebase already has two other integrations in this codebase (see Section 14)
- Free tier (Spark plan) handles this data volume easily — two tiny JSON documents per user, updated dozens of times per day

**CloudKit disadvantages for this use case:**
- Apple holds encryption keys unless using end-to-end encrypted fields, which requires additional entitlements and setup
- Harder to layer an independent passphrase-derived key on top
- No cross-platform path if Trio ever targets other platforms
- Debugging CloudKit sync issues is significantly harder

### 6.2 Per-User Firebase Projects

Each user sets up their own Firebase project. This is a deliberate design choice:

- No single entity (including the developer) has access to any user's backup data
- No shared infrastructure cost or maintenance burden
- No multi-tenancy security risks
- Users who are comfortable with Firebase can audit their own Firestore rules and storage
- Consistent with the DIY ethos of the Trio project

The tradeoff is setup friction. This is mitigated by providing step-by-step in-app guidance (see Phase 2 of implementation plan).

---

## 7. Security Architecture

### 7.1 Three-Layer Defense

**Layer 1 — Firebase Authentication (email/password + email MFA)**

Proves the person accessing the backup is the account owner. Prevents unauthorized access to the encrypted blob even if someone knows the user's Firebase project ID.

Firebase Auth supports email/password authentication with TOTP or email-based MFA out of the box. Both will be supported; email MFA is recommended as the lower-friction option.

**Layer 2 — Client-Side AES-256-GCM Encryption (passphrase-derived key)**

The backup payload is encrypted on-device before it is ever sent to Firebase. Firebase never receives the plaintext LTK or any other pod state in readable form.

Key derivation:
- User sets a memorable recovery passphrase during setup
- Derive a 256-bit encryption key using PBKDF2-SHA256 with 600,000 iterations (OWASP 2023 recommendation) and a random 32-byte salt
- The salt is stored alongside the encrypted blob in Firestore (it is not secret — it only prevents rainbow table attacks)
- The passphrase itself never leaves the device and is never stored in Firebase

On recovery: the user enters their passphrase on the new device, the same PBKDF2 derivation is run with the stored salt, and the blob is decrypted.

**Note on Argon2:** The previous discussion mentioned Argon2 as a candidate KDF. Argon2 is preferable in theory (memory-hard) but requires a third-party Swift package — it is not available in Apple's CryptoKit or CommonCrypto. PBKDF2-SHA256 with high iteration count via CommonCrypto is the native choice and is acceptable for this use case.

**Layer 3 — Automatic Expiry**

Pod state data is automatically deleted from Firestore after the pod expires (72 hours nominal + 8 hours buffer = 80 hours from activation). Firestore TTL (time-to-live) is configured on the `podExpiry` field of each document.

Old pod session documents are superseded by new pod pairings and are never accumulated.

### 7.2 Firestore Security Rules

The Firestore rules for the user's project must enforce:

```
// Only authenticated users can read/write their own documents
match /users/{userId}/{document=**} {
  allow read, write: if request.auth != null && request.auth.uid == userId;
}
```

Step-by-step rule setup is included in the in-app setup wizard.

### 7.3 What a Breach Reveals

If an attacker compromises the user's Firebase project AND the Firestore database contents:

- They obtain the encrypted blob, the IV, and the salt
- They cannot decrypt without the passphrase
- PBKDF2 with 600k iterations makes brute force of a reasonable passphrase computationally expensive (months to years on modern hardware for a 6+ word passphrase)

If an attacker also somehow obtains the passphrase (e.g., from a password manager breach):

- They can decrypt the pod state and obtain the LTK
- They would still need to be physically within Bluetooth range of the pod (~10 meters) to use it
- Active pod sessions have sequence numbers — out-of-sequence messages are rejected by the pod

This is an acceptable residual risk for a voluntary backup feature. Users should be informed that the passphrase must be kept as secure as an insulin pump access code.

---

## 8. Firestore Data Model

Two documents per user, under their Firebase Auth UID.

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

The `encryptedPayload` decrypts to JSON-encoded therapy settings.

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

Pod state sync is triggered after **every successful pod command**. This is the only strategy that guarantees the backup is always current enough to be useful for recovery:

- After bolus delivery (standard, extended, or correction)
- After temp basal set/cancel
- After suspend/resume
- After pod status poll (getStatus)
- After alert acknowledgment
- Immediately after pod pairing (first sync, includes initial LTK)

### 9.2 Offline Handling

Connectivity is not guaranteed. The sync must degrade gracefully:

1. After each successful pod command, attempt Firestore write
2. If the write fails (no connectivity, Firestore error), enqueue the current state locally in a lightweight pending-sync queue (UserDefaults key with timestamp)
3. On next app foreground or network connectivity restoration, flush the pending-sync queue
4. If the local queue has accumulated more than one pending write (multiple commands while offline), only the most recent state needs to be uploaded — intermediate states are superseded
5. Never block pod commands waiting for Firestore — the sync is always fire-and-forget from the command execution path

This means the backup could lag by however long the device was offline. This is acceptable because the pod state that matters most for recovery is the current state, not intermediate states.

### 9.3 Settings Sync Triggers

Settings sync is triggered when:

- User saves any settings change in Trio
- App launches (to catch any missed syncs)
- User explicitly taps "Sync Now" in the backup settings screen

Settings sync is less time-sensitive than pod state sync and has a simpler retry model.

---

## 10. Device Locking & Conflict Prevention

This is the most important safety mechanism in the feature. Two devices communicating simultaneously with the same pod using out-of-sync sequence numbers will cause communication failures and potentially corrupt the pod's command state.

### 10.1 Lock Semantics

Only one device may hold the active device lock at a time. The device holding the lock is the only device authorized to send commands to the pod and write to the pod backup.

### 10.2 Lock Acquisition

When a device restores from backup (new phone recovery flow):

1. Read the `deviceLock/current` document
2. Check `lastHeartbeat` — if the heartbeat is older than 10 minutes, the old device is presumed dead and the lock can be taken
3. Write the new device's ID to `deviceLock/current` with the current timestamp
4. Invalidate the local pod state on the old device (if it ever comes back online, it must see that it no longer holds the lock)

When a device detects it has lost the lock (old phone comes back online):

1. On app foreground, read `deviceLock/current`
2. If `activeDeviceId` != own device ID, present a blocking alert: "This device is no longer the active controller for your pod. Pod control has moved to another device. This device will not send any pod commands."
3. Disable all pod command pathways on the old device
4. Optionally allow the user to re-claim the lock if they are sure the new device is no longer active

### 10.3 Lock Heartbeat

The active device writes a heartbeat to `lastHeartbeat` every 5 minutes. This allows a recovering device to detect a genuinely dead old device (heartbeat stale > 10 minutes) vs. an old device that is still active (heartbeat recent).

### 10.4 Lock on Normal Device Replacement (Planned)

In a non-emergency scenario where the user is switching phones intentionally:

1. On old device: Settings → Pod Backup → "Transfer to New Device"
2. Old device writes `activeDeviceId: nil` (unlocked state) to Firestore
3. Old device disables itself from sending further pod commands
4. New device picks up the unlocked state and claims the lock

---

## 11. Recovery Flow (New Phone)

This is the primary user-facing feature. The flow must be fast, clear, and survivable by a person who is stressed, possibly hypoglycemic, and in an unfamiliar location.

### 11.1 Step-by-Step Recovery

```
1. Install Trio via TestFlight on new phone
2. Launch Trio
3. On the "Welcome" / onboarding screen: tap "Restore from Cloud Backup"
4. Enter Firebase email address
5. Enter Firebase password
6. Complete MFA (email code sent to registered email)
7. Enter recovery passphrase
   → App derives encryption key, decrypts backup from Firestore
   → Displays summary: "Found backup from [timestamp]. Pod expires [time]. 
     Therapy settings included."
8. Tap "Restore"
   → OmniBLEPumpManagerState is reconstructed from decrypted payload
   → Therapy settings are written to local storage
   → App acquires device lock in Firestore
9. App scans for nearby Dash pod via BLE
   → Matches by pod address from backup
   → See Section 12 for re-discovery detail
10. Session established using transferred LTK + eapSeq + msgSeq
11. Pod status read to confirm connection
12. ✅ Looping resumes
```

### 11.2 Failure Cases

| Failure | User-Facing Message | Resolution |
|---|---|---|
| No internet on new phone | "Cannot connect to backup service. Connect to WiFi or cellular and try again." | Retry |
| Wrong passphrase | "Incorrect passphrase. Check your passphrase and try again." | Retry (no lockout — passphrase never sent to server) |
| No backup found | "No backup found for this account." | Check email, or proceed with fresh setup |
| Pod expired | "The backed-up pod has expired. You will need to start a new pod." | Proceed with fresh pod pairing |
| Pod not found nearby | "Could not find your pod nearby. Make sure you are within range and try again." | Retry scan; see Section 12 |
| Session establishment fails | "Could not reconnect to pod. The pod may need to be deactivated." | Manual escalation |

---

## 12. BLE Re-Discovery

This is the technically interesting step in the recovery flow.

### 12.1 The Problem

`PodState.bleIdentifier` is a CoreBluetooth peripheral UUID that is assigned per iOS device. The same physical Omnipod Dash pod gets a different UUID on the new phone. The stored `bleIdentifier` is useless on the new device.

### 12.2 The Solution

1. Start a CoreBluetooth scan for peripherals advertising the Omnipod Dash service UUID
2. For each discovered peripheral, attempt to read its pod address from the advertisement data or via a preliminary BLE handshake
3. Compare the discovered pod address against `PodState.address` from the backup
4. If they match, this is the correct pod — update `bleIdentifier` to the new peripheral's UUID
5. Proceed with `establishSession(ltk:eapSeq:msgSeq:)`

### 12.3 Proximity Requirement

The user must be within Bluetooth range (~10 meters) of the pod during recovery. This is inherent to BLE and cannot be worked around. The UI should make this requirement explicit before starting the scan.

### 12.4 Multiple Pods Nearby

If the user is in a clinic or with other Dash users, there may be multiple Dash pods advertising. The pod address match uniquely identifies the correct pod. No user disambiguation is needed.

---

## 13. Firebase Project Setup (Per-User)

Setup happens once, during the "enable backup" flow in Trio settings. The app provides step-by-step guidance.

### 13.1 What the User Creates

1. A Firebase project (free, Google account required)
2. Firestore Database enabled in the project
3. Firebase Authentication enabled with email/password provider
4. MFA enabled on their Firebase Auth account
5. A user account created in Firebase Auth
6. Firestore security rules configured (provided by app)
7. Firebase project configuration file (`GoogleService-Info.plist` equivalent values) entered into Trio

### 13.2 Configuration Stored in Trio

The app needs the following Firebase project identifiers, which the user copies from their Firebase console:

- Firebase API Key
- Firebase Auth Domain
- Firebase Project ID
- Firebase App ID

These are not secrets — they are public project identifiers. The encryption passphrase and the user's password are the actual secrets.

These configuration values are stored in Trio's local settings (UserDefaults or Keychain as appropriate) and are **not** themselves backed up to Firebase (circular dependency).

### 13.3 Firestore Indexes

No composite indexes required for the initial implementation. The two documents per user are fetched by direct path, not by query.

---

## 14. Relationship to Existing Firebase Integrations

Trio on the Zack-Trio branch already has two Firebase integrations:

1. **Crashlytics / Firebase Analytics** — uses the default `GoogleService-Info.plist` Firebase app, for crash reporting
2. **Garmin data integration** — uses a second Firebase app instance for Garmin Connect IQ data relay

The Pod Cloud Backup feature adds a **third Firebase app instance**, configured with the user's own Firebase project credentials (not a shared project). This follows the same multi-app pattern already established in the codebase.

The three Firebase app instances are completely independent and do not share any project resources or credentials.

---

## 15. Phased Implementation Plan

### Phase 1 — Foundation & Core Encryption (No UI)

**Goal:** Prove the core technical loop: serialize pod state → encrypt → upload to Firestore → download → decrypt → restore.

**Tasks:**
- [ ] Create `PodCloudBackupService.swift` — handles encryption, decryption, Firestore read/write
- [ ] Implement PBKDF2-SHA256 key derivation (CommonCrypto)
- [ ] Implement AES-256-GCM encrypt/decrypt (CryptoKit `AES.GCM`)
- [ ] Implement Firestore document write for pod state payload
- [ ] Implement Firestore document read for pod state payload
- [ ] Write unit tests for encrypt/decrypt round-trip
- [ ] Write unit tests for serialization/deserialization of `OmniBLEPumpManagerState.rawValue`
- [ ] Validate that all fields in Section 5.1 survive the round-trip

**Does not include:** Firebase Auth, UI, sync triggers, device lock.

**Success criteria:** A test that takes a real `PodState`, serializes it, encrypts it, decrypts it, and reconstructs an identical `PodState`. No data loss.

---

### Phase 2 — Firebase Auth & Setup Flow

**Goal:** Users can create and configure their Firebase project and link it to Trio.

**Tasks:**
- [ ] Add third Firebase app initialization path using user-provided credentials
- [ ] Build "Enable Pod Backup" settings screen
  - Firebase API Key / Project ID / App ID entry
  - Firebase email + password sign-in
  - MFA setup / verification
  - Recovery passphrase entry and confirmation (with strength guidance)
  - Passphrase stored only in iOS Keychain on device, never uploaded
- [ ] Build Firestore security rules template (displayed in app, user copies to Firebase console)
- [ ] Build setup validation: test write → test read → confirm success
- [ ] Store Firebase config in Keychain (not UserDefaults — these are credentials)

**Does not include:** Sync triggers, recovery flow.

---

### Phase 3 — Continuous Sync

**Goal:** Pod state is automatically kept current in Firestore after every pod command.

**Tasks:**
- [ ] Identify all pod command completion points in `OmniBLEPumpManager` and `PodComms`
- [ ] Hook sync trigger at each point (post-command, on success only)
- [ ] Implement offline queue (UserDefaults-backed, lightweight)
- [ ] Implement queue flush on network restoration / app foreground
- [ ] Implement settings sync on settings save
- [ ] Add sync status indicator in settings screen ("Last synced: 2 minutes ago")
- [ ] Add sync error banner (non-blocking) when sync has been failing for > 30 minutes
- [ ] Implement device heartbeat (5-minute interval, updates `deviceLock.lastHeartbeat`)

---

### Phase 4 — Device Lock

**Goal:** Prevent two devices from commanding the same pod simultaneously.

**Tasks:**
- [ ] Implement device ID generation (persistent UUID per app install, stored in Keychain)
- [ ] Implement lock acquisition on first sync after backup enable
- [ ] Implement lock check on app foreground
- [ ] Implement lock-lost detection and pod command disablement
- [ ] Implement "Transfer to New Device" intentional handoff flow
- [ ] Implement stale lock override (heartbeat > 10 minutes old)

---

### Phase 5 — Recovery Flow

**Goal:** Full end-to-end recovery on a new phone, including BLE re-discovery.

**Tasks:**
- [ ] Add "Restore from Cloud Backup" option to Trio onboarding/welcome screen
- [ ] Build recovery UI: email → password → MFA → passphrase → preview → restore
- [ ] Implement Firestore read + decrypt on new device
- [ ] Implement `OmniBLEPumpManagerState` reconstruction from decrypted payload
- [ ] Implement BLE re-discovery scan (CoreBluetooth scan + pod address matching)
- [ ] Implement `bleIdentifier` update after re-discovery
- [ ] Implement session establishment using recovered LTK
- [ ] Implement all failure cases from Section 11.2
- [ ] End-to-end test: physical pod transfer between two physical iPhones

---

### Phase 6 — Polish & Safety Hardening

**Goal:** Production-ready, safe for medical use.

**Tasks:**
- [ ] Firestore TTL configuration (auto-delete on `podExpiry`)
- [ ] Backup data version migration path (for future schema changes)
- [ ] Recovery passphrase change flow (re-encrypt and re-upload with new key)
- [ ] "Delete My Backup" option (user can purge their data from Firestore)
- [ ] Backup health dashboard: last sync time, pod expiry, device lock status
- [ ] Security review of encryption implementation
- [ ] Documentation for users: setup guide, recovery guide, passphrase management guide
- [ ] TestFlight beta with a small group of experienced users

---

## 16. Open Questions & Risk Register

| # | Question / Risk | Severity | Resolution |
|---|---|---|---|
| 1 | What happens if eapSeq or msgSeq is stale at time of recovery (old phone sent commands after last backup)? | High | Pod will reject session with out-of-sequence error. Session establishment includes retry with incremented counters. Need to characterize the pod's tolerance window. |
| 2 | Is PBKDF2-SHA256 at 600k iterations fast enough on older iPhones for a good UX? | Medium | Benchmark on iPhone 11 (oldest likely device). If too slow, reduce iterations or switch to scrypt. |
| 3 | Firebase free tier limits (Firestore writes: 20k/day). Will sync frequency stay within limits? | Low | ~50–100 writes/day typical. 20k/day limit gives 200x headroom. Throttle sync to max 1 write per 30 seconds if needed. |
| 4 | User loses passphrase. | High | There is no recovery path — this is by design (we cannot store the passphrase). Document this clearly. Encourage users to store passphrase in password manager. Offer a passphrase change flow so users can rotate if they fear compromise. |
| 5 | User loses Firebase credentials (email/password). | Medium | Standard Firebase password reset via email. MFA recovery codes should be saved. Document this. |
| 6 | Pod firmware update changes BLE advertisement format, breaking re-discovery. | Low | Monitor OmniBLE updates. Re-discovery logic should be abstracted to make this easy to update. |
| 7 | Two physical phones both online simultaneously try to sync conflicting state. | High | Device lock (Section 10) prevents this. Last-write-wins is acceptable if lock is correctly enforced. |
| 8 | Apple rejects app due to Firebase dependencies or background processing. | Low | Firebase is widely used in App Store apps. Background processing limited to existing BGTask patterns already in Trio. |

---

*This document is a pre-implementation specification. It describes intent and design, not completed code. All implementation decisions are subject to revision as development proceeds.*
