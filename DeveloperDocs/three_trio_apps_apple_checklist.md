# Three Trio apps: Apple / GitHub checklist

This fork builds three separate iPhone apps from three branches. CI can create
identifiers, but Apple Developer and App Store Connect still need a one-time
setup for the two extra apps.

| Branch | App name | Bundle ID | App group | URL scheme |
| --- | --- | --- | --- | --- |
| `upgrade/trio-1.0` | Trio | `org.nightscout.TEAMID.trio` | `group.org.nightscout.TEAMID.trio.trio-app-group` | `Trio` |
| `main` | Trio Main | `org.nightscout.TEAMID.trio.main` | `group.org.nightscout.TEAMID.trio.main.trio-app-group` | `TrioMain` |
| `dev` | Trio Dev | `org.nightscout.TEAMID.trio.dev` | `group.org.nightscout.TEAMID.trio.dev.trio-app-group` | `TrioDev` |

Replace `TEAMID` with your Apple Team ID. The current TestFlight app on
`upgrade/trio-1.0` keeps its existing bundle ID.

Follow the same Apple steps as [fastlane/testflight.md](../fastlane/testflight.md),
once per extra app. Without these steps CI can compile, but TestFlight upload
fails.

## 1. Add Identifiers

Run **Actions → 2. Add Identifiers** on `main`, then again on `dev`. The
workflow rewrites `Config.xcconfig` for that branch before Fastlane, so the new
IDs are created for `…trio.main` and `…trio.dev` (plus watch / Live Activity
suffixes).

Do not rerun this on `upgrade/trio-1.0` unless you are repairing the existing
Trio identifiers.

## 2. Create App Groups

In [Register an App Group](https://developer.apple.com/account/resources/identifiers/applicationGroup/add/):

| Description | Identifier |
| --- | --- |
| Trio Main App Group | `group.org.nightscout.TEAMID.trio.main.trio-app-group` |
| Trio Dev App Group | `group.org.nightscout.TEAMID.trio.dev.trio-app-group` |

Attach each group to that app’s Trio, Watch App, and Watch Complication
identifiers. Live Activity does not need the app group.

## 3. Create App Store Connect apps

In [App Store Connect](https://appstoreconnect.apple.com/apps), create two new
iOS apps (the on-phone name comes from `APP_DISPLAY_NAME`, not the ASC name):

- One app whose bundle ID is `org.nightscout.TEAMID.trio.main`
- One app whose bundle ID is `org.nightscout.TEAMID.trio.dev`

SKU can be anything unique. You do not need to submit these apps to the store.

## 4. Time Sensitive Notifications

On the new Trio identifiers (`…trio.main` and `…trio.dev`), enable **Time
Sensitive Notifications** in
[Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list).
This is only required on the main app identifier, not watch or Live Activity.
See [Enable Time Sensitive Notifications](../fastlane/testflight.md#enable-time-sensitive-notifications).

## 5. TestFlight Internal Testing

In App Store Connect, open each extra app and add it to **TestFlight → Internal
Testing**. Add the same testers you already use for Trio.

## 6. GitHub default branch

Set the repository default branch to `upgrade/trio-1.0`. Scheduled “Build Trio”
runs use the default branch; leaving `main` as default would build the clean
Trio Main app instead of the daily TestFlight app.
