# Plugin fetch Combine contract tests

Run on macOS with Xcode selected and Python 3:

```sh
python3 scripts/tests/plugin-fetch/run.py
python3 scripts/tests/plugin-fetch/run.py --full-timeout
```

These XCTest cases compile the **current `PluginSource.fetch(_:)` method**, extracted from source, against Apple's Combine. They require neither submodules nor signing. To compare a baseline without editing your checkout:

```sh
git show a708381782825c03745db1c6377efe632b5f2161:Trio/Sources/APS/CGM/PluginSource.swift > /tmp/PluginSource-before.swift
python3 scripts/tests/plugin-fetch/run.py --source /tmp/PluginSource-before.swift
```

The default run shortens only the timeout to 40 ms. `--full-timeout` leaves the method text unchanged and waits through the actual five-minute timeout. Both compile with warnings as errors.

## Coverage and boundaries

- Empty array and empty completion: exactly one empty value, then completion.
- Nonempty array: unchanged; later values/errors do not produce another value.
- Silent publisher: timeout produces one empty value and cancels upstream.
- Event order, upstream cancellation, downstream cancellation, finite demand, and asynchronous Future callback.
- Defensive outer error replacement is exercised with a failing publisher. Production `fetchIfNeeded()` has `Failure == Never`, so this is not a reachable plugin callback error scenario.

The test-only host injects the `fetchIfNeeded()` publisher, substitutes synthetic integer elements for `BloodGlucose`, and supplies a serial DispatchQueue. This is a source-extracted **operator contract** suite, not an integration test of the PluginSource class, CGM drivers, UIKit, Core Data, app background execution, or pump scheduling. Signature/timeout changes fail the extractor so it must be reviewed rather than silently using a stale operator copy. Tests are not wired into the iOS TrioTests target.

The original `Collection.isEmpty` / Combine Filter `EXC_BAD_ACCESS` has **not** been reproduced by these tests. Empty Swift arrays are valid; removing that closure is not proof that an underlying memory-lifetime or concurrency problem is resolved.

## Scheduling review

`fetchIfNeeded()` currently resolves the Future with `[]` when the plugin fetch callback returns. Actual readings/backfill use `cgmManager(_:hasNew:)` → `newGlucoseFromCgmManager`, independently of this publisher (see PR #703). This change intentionally makes the empty result observable by the timer subscriber instead of completing without a value. The existing `glucoseStoreAndHeartDecision` empty-data guard returns before storage, pump heartbeat schedule updates, or `heartbeat`. It does acquire the existing semaphore and begin/end a background task first. The timer interval, BLE capability, delegate queue, and share-client suppression are unchanged. Device-level scheduling remains a maintainer/integration validation concern, not a claim of these tests.
