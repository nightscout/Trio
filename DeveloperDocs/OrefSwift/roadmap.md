# Roadmap

At this point, we have a complete port of the oref algorithm from
Javascript to Swift. At a high level, the three steps we want to go
through are:

  - Small scale testing
  - Beta testing shadow mode
  - Beta testing swift algorithm
  - Release

## Small scale testing

At this stage, the implementation is in the `Trio-dev` repo and there
are a small number of known testers running the algorithm. The Swift
implementation runs in shadow mode where we execute it, compare the
results against JS, and log any inconsistencies for further analysis.

The exit criteria for this stage is:

  - Ensure no inconsistencies for the large database (200k+) of inputs
    we have.

  - Fix any known bugs in the Swift implementation (all documented via
    GitHub issues)

  - Do an analysis on the algorithm bugs we fixed in Swift to confirm
    that the resulting changes to the algorithm are safe and within
    our expected bounds.

  - Add the ability to test fixed JS in the app before logging
    inconsistencies to reduce the logging volume.

## Beta testing shadow mode

At this stage, we move the algorithm to the main `Trio` repo on the
dev branch. The Swift implementation is still running in shadow mode
while we collect more data.

The exit criteria for this stage is:

  - No inconsistencies in the algorithm for one week of operation

## Beta testing swift algorithm

At this stage, we move to using the Swift implementation for dosing
decisions, but we keep the JS implementation to check for
inconsistencies and log inputs for any inconsistent runs.

The exit criteria for this stage is:

  - No inconsistencies in the algorithm for one month of operation

## Release

At this stage, the port is complete. The swift code is running and we
productionize the implementation.

Productionization includes:

  - Removing the JS implementation from the repo

  - Refactoring the replay mechanism or removing it depending on if we
    want to use it for other features in the future