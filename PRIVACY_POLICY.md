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

You can opt out of crash reporting at any time through the Trio
settings. If you opt out:

- No new crash data will be collected or sent to us
- Previously collected crash data will still be retained for approximately 90 days

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
