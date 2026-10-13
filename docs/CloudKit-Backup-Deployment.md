# CloudKit settings backup — deployment guide

Provision CloudKit for Trio's signing identity and validate backup and restore
on an iPhone signed into iCloud.

## Snapshot data

Schema 5 stores therapy and algorithm settings, basal rates, insulin
sensitivities, carb ratios, glucose targets, saved adjustment and meal presets,
and app and alert configuration. Dynamic ISF historical TDD summaries have
their own checksum. The configuration fingerprint determines when changed
settings need an automatic backup.

## Automatic backups and retention

- Compare the saved configuration once per elapsed 24 hours after the last
  completed comparison. A changed configuration queues a new snapshot.
- Perform overdue checks on launch or foreground, and schedule the next check
  while Trio stays running.
- Keep queued snapshots on disk through network failures and app termination,
  and retry uploads when Trio becomes active.
- Support immediate named manual backups and portable JSON export/import.
- Apply the configured retention limit separately to manual and automatic
  backups, removing the oldest records as needed.

## Restoration

- Complete preflight validation with the pump unpaired before applying settings.
- Start and finish restoration in Open Loop.
- Restore file-backed configuration, Core Data preset templates, and eligible
  Dynamic ISF summaries under a rollback journal.
- Recover interrupted restores at startup before app and dosing services initialize.
- Use Trio’s existing Dynamic ISF readiness check. When local history is
  insufficient, fill missing five-minute slots with summaries from the last ten
  days, preserving original timestamps and existing local samples.
- Review therapy settings, basal delivery limits, and insulin concentration
  before pairing a pump after restoration.

## Storage and validation

CloudKit uses the user's private database and encrypted fields for snapshot
payloads, names, and configuration fingerprints. Each backup carries a schema
version and integrity checks. Import and download validate compatibility,
size, settings, and checksums before restoration.

The encoded CloudKit payload limit is 750,000 bytes. Portable JSON backup files
support up to 8 MiB.

## Configuration

1. Enable iCloud/CloudKit on the Apple Developer App ID signing Trio.
2. Set the container to `iCloud.$(PRODUCT_BUNDLE_IDENTIFIER)` and ensure it
   appears in app entitlements and provisioning profiles.
3. Initialize the development CloudKit schema and deploy it to production.
   TestFlight uses the production CloudKit environment.
4. Verify account and container access on the signed iPhone. Backups belong
   to that iCloud account and CloudKit container.

## Validation

- Build Trio and its test targets, and run the focused CloudKit tests.
- Validate named manual backups, local export/import, saved-value previews,
  and restoration of downloaded CloudKit backups on a signed iPhone.
- Check the daily comparison interval with both configuration edits and
  additional Dynamic ISF history.
- Verify queued uploads survive termination and retries preserve backup identity.
- Check manual and automatic retention limits and oldest-backup removal.
- Verify pump preflight, Open Loop restoration, and therapy setting review.
- Test rollback and startup recovery after failures in each journal, file,
  Core Data, and history phase.
- Test iCloud account changes, disabled iCloud, limited storage, network
  failures, and restoration after reinstall.
- Review timeouts, concurrent operations, and CloudKit quota handling.
