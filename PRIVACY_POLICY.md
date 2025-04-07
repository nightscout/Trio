# Privacy Policy

## Introduction

This Privacy Policy explains how we collect, use, and share
information when you use Trio. We respect your privacy and are
committed to protecting your personal data. Please read this Privacy
Policy carefully to understand our practices regarding your personal
data.

## Information We Collect

### Crash Reporting (Opt-In by default, with ability to Opt-Out)

Our App uses Google Firebase Crashlytics to collect crash reports. You
will be asked to opt in to crash reporting when you first use Trio,
and you can change this setting at any time.

For users who use Trio without going through the onboarding process,
we opt them in to crash reporting by default, but you can opt out at
any time.

The following information may be sent to Crashlytics when the App
crashes:

- Time and date of the crash
- Device state at the time of the crash
- Stack trace information
- Device model and OS version
- A generated unique identifier (not personally identifiable)

### Debug Symbols (dSYMs)

As an open source project, our build scripts upload debug symbols
(dSYMs) to Google's servers. We use these files to give us
deobfuscated and human-readable crash reports, and contain mapping
information that helps us interpret crash reports. dSYM files only
contain code-related mapping information to decode a stack-trace into
a readable format, such as function names, class names, method names,
and line numbers. They are used to create human-readable crash reports
to help us understand crashes. These files do not contain any personal
information about you or your device usage.

## How We Use Your Information

We use anonymous crash report information exclusively to:

- Identify and fix bugs and crashes
- Improve the App's stability

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
be visible to project contributors who help maintain and improve the
App. All contributors are expected to adhere to this privacy policy
and handle any data responsibly.

## Opting Out

You can opt out of crash reporting at any time through the Trio
settings. If you opt out:

- No crash data will be collected or sent to us
- Previously collected crash data will still be retained as described below

To avoid sending dSYMs to Crashlytics, you can delete the Trio target
Build Phase script, titled "Copy dSYMs to Crashlytics".

## Data Retention

Crash data and associated debugging information are retained only as
long as necessary to analyze and fix issues. Typically, this is for a
period of 90 days.

## Your Rights

You have certain rights regarding your personal information,
including:

- The right to access the information we have about you
- The right to request deletion of your data
- The right to opt-out of crash reporting (as described above)

To exercise these rights, please contact us using the information
provided below.

## Changes to This Privacy Policy

We may update this Privacy Policy from time to time. We will notify
you of any changes by posting the new Privacy Policy on this page and
updating the "Last Updated" date.

## Contact Us

If you have any questions about this Privacy Policy, please contact us
on [Discord](http://discord.diy-trio.org/).

## Last Updated

April 6th, 2025