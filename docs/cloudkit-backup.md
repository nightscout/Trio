# CloudKit settings backup

Trio saves versioned settings snapshots to the user's private iCloud database.
Backups include therapy and algorithm settings, schedules, saved presets,
app and alert configuration, and Dynamic ISF historical TDD summaries.
Settings can be restored during onboarding or from Backup & Restore.

## Backup management

- Create a named iCloud backup with Back Up Now.
- Browse manual and automatic backups in View Backups, and inspect their
  saved values in read-only settings screens.
- Export the current configuration or a saved iCloud backup as a portable
  JSON file, and import a local backup file for review and restoration.
- Use Configuration to enable automatic backups and choose separate
  retention limits for manual and automatic iCloud backups. Trio removes
  the oldest backups as needed to keep each type within its limit.

## Daily automatic backups

Trio compares the saved configuration with the last backed-up configuration
once every 24 hours. A changed configuration creates a new snapshot for upload.
The comparison covers settings, schedules, presets, and app configuration;
Dynamic ISF history is included when a snapshot is created.

Checks run on launch or when Trio becomes active. An in-process task schedules
the next daily check while Trio stays running, and an overdue check runs when
the app next becomes active. Queued uploads persist locally and retry when
Trio is active. Manual backups can be created at any time.

## Restoration

Unpair the pump before restoring. Trio validates the backup, applies its
settings in Open Loop, and restores saved preset templates. A journal supports
rollback and recovery at startup after an interrupted restore. Review therapy
settings before pairing the pump again.

Dynamic ISF restoration uses Trio’s existing readiness check. When local history
is insufficient, saved summaries from the last ten days fill missing five-minute
slots. Original timestamps and existing local samples are preserved.

## Implementation

- `CloudSettingsBackup.swift`: snapshot and saved preset models.
- `SettingsBackupValidator.swift`: normalization, integrity checks, and schema compatibility.
- `SettingsBackupDynamicISF.swift`: historical TDD capture and validation.
- `CloudKitBackupStore.swift`: private CloudKit records and encrypted settings payloads.
- `TrioCloudBackupCoordinator.swift`: daily comparisons, durable upload queue, manual backups, and retention.
- `TrioCloudSettingsRestore.swift`: restoration preflight and settings application.
- `TrioCloudRestoreTransaction.swift`: restore journal, rollback, and crash recovery.
- `TrioCloudRestoreHistory.swift`: eligible Dynamic ISF history merge.
- `TrioCloudRestorePresets.swift`: preset persistence and verification.
- `TrioCloudBackupView.swift`: Backup & Restore entry screen and local file operations.
- `BackupSettingsPreviewView.swift`: read-only saved settings, schedules, presets, and history summaries.

See [CloudKit Backup Deployment](CloudKit-Backup-Deployment.md) for
provisioning and validation.
