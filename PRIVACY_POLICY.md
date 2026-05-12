# Privacy Policy

## Introduction

This Privacy Policy explains how we collect, use, and share
information when you use Trio. We respect your privacy and are
committed to protecting your personal data. Please read this Privacy
Policy carefully to understand our practices regarding your personal
data.

## Information We Collect

### What We Do NOT Collect

For complete transparency, we want to clarify that Trio does not collect:
- Blood glucose (BG) readings
- Treatment data
- Total daily doses (TDD)
- Any health-related statistics or personal medical information
- Personal identifiable information such as name, address, or email

### Crash Reporting (Opt-In by default, with ability to Opt-Out)

Trio uses Google Firebase Crashlytics to collect crash reports. During
the initial app setup (onboarding process), you will be asked to opt
in to crash reporting. The onboarding process is the series of screens
you see when first launching Trio that helps you set up the app.

The following information may be sent to Crashlytics when Trio crashes:

- Time and date of the crash (example: "Trio crashed on April 6, 2025 at 2:15 PM")
- Device state at the time of the crash (example: "Trio was in the foreground" or "Battery level was 42%")
- Stack trace information (technical information showing which line of code failed)
- Device model and OS version (example: "iPhone 14 Pro running iOS 17.4.1")
- A generated unique identifier (a random code like "A7B2C9D3" that doesn't identify you personally)

### Anonymous Usage Telemetry (Opt-In by default, with ability to Opt-Out)

Trio can periodically send a small anonymous usage report to a
self-hosted telemetry endpoint operated by the Trio team. No
third-party analytics service is involved. You are asked about this
choice during onboarding (alongside crash reporting); existing users
upgrading from a pre-telemetry build are prompted once on the first
app launch after the update. You can change your choice at any time
in Settings → App Diagnostics, and you can inspect the exact JSON
that would be sent under "What's sent" on that same screen.

Telemetry requests are authenticated with Apple App Attest. This
means Apple cryptographically vouches for the fact that the request
came from a genuine, unmodified copy of Trio running on a real
Apple device. App Attest does not transmit any personal data,
device identifiers, or location information; it produces a one-way
attestation that the server validates with Apple. Devices that do
not support App Attest (e.g. the iOS Simulator) silently skip
sending telemetry.

The diagnostics-sharing selection offers three options:

- **Enable Full Sharing** — crash reports AND anonymous usage telemetry.
- **Crash Reports Only** — crash reports, no usage telemetry.
- **Disable Sharing** — neither.

The following information is included in the telemetry payload:

- App version, build date, branch, and commit SHA
- Whether the build is a TestFlight or App Store / sideload build
- An Apple-supplied per-vendor identifier (IDFV) and a per-install UUID
- Device hardware identifier (e.g. "iPhone15,2"), platform, and iOS version
- The paired pump model (when a pump is configured)
- The paired CGM type and model (when a CGM is configured)
- Whether Nightscout, Tidepool, and Apple Health are configured (yes/no — no URLs, tokens, or credentials)
- A small set of preference flags: units (mg/dL or mmol/L), closed-loop
  on/off, Live Activity enabled, calendar integration enabled
- A rolling 7-day count of how often the app was cold-launched
- The commit SHAs of pinned submodules (e.g. LoopKit, OmniBLE)

The payload sends once every 24 hours while the app is running, plus
once after a new build is installed. Sending failures simply retry on
the next launch or scheduler tick — there is no continued retry.

### What Telemetry Does NOT Include

- Glucose readings, insulin doses, carb entries, or any therapy data
- Therapy settings (basal rates, ISF, carb ratio, glucose targets, max bolus, max basal)
- Your Nightscout URL or API token
- Your Tidepool email, password, or session token
- Remote-command secrets or APNS keys
- Time zone or location
- App logs — log sharing remains a separate, user-initiated flow under Settings

### Debug Symbols (dSYMs)

When we build the Trio app, we create special files called debug
symbols (dSYMs) that help us read crash reports. Think of these like a
decoder ring for crashes:

Without dSYMs, a crash might look like: "Error at memory address
0x1234ABCD" With dSYMs, we can see: "Error in function
'calculateInsulin' at line 157"

These files only contain code-related information that helps us
understand where crashes happen. They contain no personal information
about you or how you use Trio.

## How We Use Your Information

We use anonymous crash report information exclusively to:

- Identify and fix bugs and crashes
- Improve Trio's stability

We do not use this information for any other purpose, such as
analytics, marketing, or user profiling.

## Data Sharing and Third-Party Services

### Crashlytics

We use Google Firebase Crashlytics to collect and analyze crash
reports. Crashlytics' privacy practices are governed by the [Google
Privacy Policy](https://policies.google.com/privacy). For more
information about how Crashlytics processes data, please visit their
documentation.

### Open Source Contributors

As an open source project, crash reports and debugging information may
be visible to project contributors who help maintain and improve
Trio. All contributors are expected to adhere to this privacy policy
and handle any data responsibly.

## Opting Out and Data Retention

You can opt out of crash reporting and/or anonymous usage telemetry
at any time through Settings → App Diagnostics in Trio. The three
options ("Enable Full Sharing", "Crash Reports Only", "Disable
Sharing") apply to both data streams. If you opt out of crash
reporting:

- No new crash data will be collected or sent to us
- Previously collected crash data will still be retained for approximately 90 days

If you opt out of anonymous usage telemetry, no new telemetry data
will be collected or sent. Previously sent telemetry rows are retained
on the Trio team's telemetry endpoint per its own retention policy.

To avoid sending dSYMs to Crashlytics, you can delete the Trio target
Build Phase script, titled "Copy dSYMs to Crashlytics".

## Your Rights

You have certain rights regarding your information, including:

- The right to opt-out of crash reporting
- The right to request deletion of your data

To opt-out of crash reporting, please see the section above for
details about how to configure Trio to not record crash reports.

The information we store is anonymous, so we are unable to look up
information for a particular individual. However, our general data
retention policy ensures that data older than 90 days is deleted,
enabling us to accommodate data deletion requests by design despite
having anonymous data.

## Changes to This Privacy Policy

We may update this Privacy Policy from time to time. We will notify
you of any changes by posting the new Privacy Policy on this page and
updating the "Last Updated" date.

## Contact Us

If you have any questions about this Privacy Policy, please contact us
on [Discord](http://discord.triodocs.org/) or send us an email at
trio.diy.diabetes@gmail.com.

## Last Updated

May 14, 2025
