# Tandem testing branch

This branch is `nightscout/Trio` `dev` plus the wiring that makes Trio offer
**Tandem Mobi** when you add a pump. It adds
[TandemKit](https://github.com/jwoglom/TandemKit) as a submodule, pinned to
commit `50cb9f9` of its `main` branch, and touches four things in Trio itself:
the device catalog entry, the alert catalog, the Xcode workspace/project, and
the tests that cover those. Every other submodule stays at the revision `dev`
pins.

**TandemKit is for experimental use only.** It is a community-built driver for
a pump nobody has approved for this purpose, running in an app nobody has
approved for this purpose. Nothing here is medical advice, and running it is
not a supported Trio configuration — discuss changes to how you dose insulin
with your diabetes care team, and keep a way to deliver insulin that does not
depend on this branch.

## Before you start

TandemKit is a **private repository**. Ask its maintainer (jwoglom) for access
first — without it, every step below fails when it reaches the TandemKit
submodule. If you plan to use the GitHub browser build, the `GH_PAT` secret in
your fork also has to be able to read TandemKit, not just your own repos:
`build_trio.yml` checks out submodules recursively with that token.

You also need a Tandem Mobi and its pairing code. Trio talks to the pump
directly over Bluetooth; it does not go through the Tandem mobile app.

## Getting the branch into your fork

Both routes end with a `feat/tandem-closed-beta` branch on your fork. Pick
whichever you prefer.

### In the browser

1. On your Trio fork, create a branch named `feat/tandem-closed-beta`. GitHub
   always branches from an existing branch, so start it from your `dev`.
2. Open this link, replacing `YOUR-USERNAME` (and the repo name, if your fork
   isn't called `Trio`):

   ```
   https://github.com/YOUR-USERNAME/Trio/compare/feat/tandem-closed-beta...nightscout:Trio:feat/tandem-closed-beta?expand=1
   ```

   That opens a pull request **into your own fork's branch** — not into
   nightscout/Trio.
3. Create the pull request, then merge it.

If the pull request shows conflicts, your branch started from something other
than an up-to-date `dev`. The local route below avoids that.

### Locally

If you don't have a clone yet:

```bash
git clone --recurse-submodules https://github.com/YOUR-USERNAME/Trio.git
cd Trio
```

Then copy this branch into your fork:

```bash
git remote add nightscout https://github.com/nightscout/Trio.git
git fetch nightscout feat/tandem-closed-beta
git push origin nightscout/feat/tandem-closed-beta:refs/heads/feat/tandem-closed-beta
```

Your fork now has the branch, with no merge commit. This only works if you
don't already have a branch of that name carrying commits of your own.

To build it on your Mac:

```bash
git checkout feat/tandem-closed-beta
git submodule update --init --recursive
```

Open `Trio.xcworkspace`, select the **Trio** scheme, and build as usual.

### Signing

Put your Apple Developer Team ID in a `ConfigOverride.xcconfig` one directory
above the repo — so if the clone is at `~/workspaces/Trio`, the file goes at
`~/workspaces/ConfigOverride.xcconfig` — containing:

```
DEVELOPER_TEAM = ABCDE12345
```

`Config.xcconfig` includes that path if it exists. Keeping it outside the repo
means it survives fresh clones and branch switches, and can never be committed
by accident.

## What's wired up, and what isn't

**In the picker.** Tandem appears as its own manufacturer with one model,
Mobi. Onboarding offers basal rates from the pump's own grid: 0.1–15.0 U/hr in
0.01 steps (the pump also supports 0, which Trio drops because the algorithm
rejects a zero basal rate).

**Pump events.** A cartridge change arrives as a rewind event, the same as any
tubed pump, so the "rewind resets autosens" setting behaves as it does on
MiniMed and Dana.

**Alerts.** TandemKit forwards pump alarms, malfunctions and alerts to Trio.
Trio's alert catalog classifies them, which is what puts them under your Device
Alarms tier settings — tone, Play Sound, Override Silence & Focus, day/night
window, per-tier snooze. Alarms and malfunctions (occlusion, empty or removed
cartridge, pump reset, battery shutdown, resume-pump, auto-off, temperature,
altitude, pressure, stuck button, invalid date) are Critical. Alerts (low
insulin, low battery, incomplete bolus or cartridge change, connection errors)
are Time-Sensitive. A notification whose condition Trio doesn't recognize still
lands in its category's tier, so a firmware update that adds an alarm cannot
quietly demote it.

**Not wired up: the pump's CGM alerts.** TandemKit can forward them, off by
default. Those forwarded alerts bypass the Device Alarms configuration — they
arrive at the level TandemKit picked. Trio raises its own glucose alarms from
its own CGM source, so leave forwarding off unless you are specifically testing
it.

**Not wired up: Control-IQ.** This is the one to think hardest about. Trio and
Control-IQ are both closed-loop systems; if the pump is running its own
automation while Trio is dosing, two algorithms are making insulin decisions
from the same data and neither knows about the other. TandemKit tracks the
pump's Control-IQ state, but Trio does not currently block or warn on it.

## Testing checklist

Start conservative — low insulin volumes, close supervision, and somewhere you
can watch what happens.

- **Pairing.** Pair, then force-quit Trio and reopen it: the pump should
  reconnect without re-pairing. Try walking out of range and back.
- **Basal.** Confirm the basal profile Trio reads matches the pump. Let Trio
  set a temp basal, then check the pump's own history screen agrees.
- **Bolus.** Deliver a small bolus from Trio; confirm the amount and timestamp
  match on the pump, and that Trio's IOB reflects it. Cancel a bolus midway and
  confirm Trio records what was actually delivered, not what was requested.
- **Suspend and resume.** Suspend from Trio, resume from the pump, and check
  Trio notices the state change.
- **Cartridge change.** Do a full change and confirm Trio logs a rewind and a
  prime, and that the reservoir reading updates.
- **Alerts.** Trigger something harmless (low insulin, or disconnect the pump
  long enough for a connection alert). Check it reaches you as a notification,
  appears in Trio's alert history, and respects the tier settings you chose in
  Device Alarms.
- **Loop behaviour.** Watch a few loop cycles: enacted doses, pump history
  sync, and whether anything stalls after a long BLE gap.

## Reporting problems

Driver behaviour — pairing, Bluetooth, pump commands, pump history parsing —
belongs in the [TandemKit](https://github.com/jwoglom/TandemKit) repository.
Trio behaviour — the picker, alerts, loop decisions, anything in the UI —
belongs in [nightscout/Trio](https://github.com/nightscout/Trio). When in
doubt, include which one you built, the Trio version from Settings, and the
TandemKit commit this branch pins.

Include logs where you can, and scrub anything identifying before you post
them.

## Open items for this branch

These are known and not yet done; they don't block testing, but they need
settling before any of this goes near `dev`:

- TandemKit is pointed at `jwoglom/TandemKit` directly. Every other Trio
  submodule points at a `loopandlearn` fork, and `scripts/define_common_trio.sh`
  (which drives the submodule bump script) only knows about those.
- No `CODEOWNERS` entry for `TandemKit`.
- The pump's CGM alerts are uncatalogued, as described above.
- Nothing in Trio reacts to the pump's Control-IQ state.
