# Replaying inputs for oref

To debug and verify our swift oref implementation, we replay inputs
caputed from real devices. This document outlines the two main use
cases for this replay mechanism: verification and daily verification.
It also shows how to debug when you find an inconsistency.

## Verification

To verify our swift oref implementation, we replay a large number of
inputs that have caused inconsistencies in the past. If our swift
implementation is correct, these previously incorrect runs will now be
consistent with either the JS implementation or our fixed JS
implementation, which is present only in our testing bundle.

To do a verification run:

```bash
# In Trio-oref, check out the latest `oref-swift` branch
$ cd Trio-oref
$ git checkout oref-swift

# In trio-oref-logs get the latest inputs
$ cd ../trio-oref-logs
$ ./update_trio_stats.sh # will take a long time for the first run

# extract all inputs from the logs
$ python extract_inputs.py

# run the verification script
$ python run_tests_on_existing_errors.py
```

This verification script will run through all of the inputs, separated
by timezone, and either confirm that all inputs produce correct outputs
or flag any timezones that had incorrect runs.

## Daily verification

Each day as new logs come in, you can run through the logs to see if
there are any inconsistencies. To do this, you run:

```bash
# Fetch the latest logs incrementally
$ ./update_trio_stats.sh
# run through all of the inputs for a single day
$ python run_tests_on_errors.py 2025-12-06 > 2025-12-06.txt
```

Then once it's done running it'll give you a report to let you know if
there were any inconsistencies found. That report will look something
like this:

```
(venv) kingst@Sams-MacBook-Pro-4 trio-oref-logs % tail 2025-12-06.txt 

--- Summary---
- autosens: 10 errors, Xcode tests: ✅
- determineBasal: 11 errors, Xcode tests: ❌ Failed for: America/Los_Angeles
- iob: 521 errors, Xcode tests: ✅
- profile: 0 errors, Xcode tests: N/A
- meal: 1178 errors, Xcode tests: ✅
```

This summary shows that all of the `autosens`, `iob`, and `meal`
inputs were consistent when run within the unit test, `profile` didn't
have any inconsistencies, and `determineBasal` had one or more replay
runs where there was an inconsistency for records in the
America/Los_Angeles timezone.

## Debugging

If you get an error, you need to step through the code and debug it. I
haven't found a good way to do this in an automated fashion yet, so
this is a highly manual process.

From an architecture perspective, there are three key
components. First, there is a local HTTP server that runs within the
`trio-oref-logs` repo to serve up inputs for replay. We use a local
HTTP server to enable us to access a large number of input logs from
within our iOS app running on a simulator.

Second, there is the iOS unit test. This test will download a list of
files from the HTTP server, download files one-by-one, and run the
appropriate function on it (e.g., `determineBasal`) to test against
the production JS implementation and a [JS
implementation](https://github.com/kingst/trio-oref/tree/dev-fixes-for-swift-comparison)
that has the bug fixes we added to Swift. It also formats the inputs
in a way that is suitable for running with the JS implementation using
mocha.

Third, the JS implementation includes unit tests for replaying inputs
created by the iOS test.

With this architecture, you can debug the same input on both the JS
and Swift implementations.

Here is an example of debugging the `determineBasal` bug from the
2025-12-06 daily verification run that we list above.

First, extract out the inputs for that particular day and serve them
using our HTTP server:

```bash
$ cd trio-oref-logs
$ rm errors/*
$ ./extract_errors.sh determineBasal 2025-12-06
$ python serve_errors.py
```

Next, open up xcode and set up the ConfigOverride.xcconfig file:

```
ENABLE_REPLAY_TESTS = YES
REPLAY_TEST_TIMEZONE = America/Los_Angeles
HTTP_FILES_OFFSET = 0
HTTP_FILES_LENGTH = 2500
```

Run the unit test that will run through all of the errors:
`DetermineBasalJsonTests.replayErrorInputs`

Search through the console for the string "REPLAY ERROR" -- this will
show you what was different and will tell you which input file caused
the error.

Then, update the unit test that runs for a single input, in our case
`DetermineBasalJsonTests.formatInputs` and copy in the name of the
input file. It will look something like this:
`/files/f1d04efa-c39b-4f0a-9955-65ab663ff9fb.0.json`. Confirm that the
test is still failing. This run will also create the inputs for use
with JS replay tests.

Search through the console and look for the string "writing" to find
the location on your local file system for the inputs formatted for
the JS replay unit test.

From the JS repo that has the fixed JS implementation, copy in the inputs:

```bash
$ cd trio-oref
$ git checkout dev-fixes-for-swift-comparison
$ cp /Users/kingst/Library/Developer/CoreSimulator/Devices/98ED1614-33B5-4F12-906B-D5C092AD0EB5/data/Containers/Data/Application/F9F20EFC-128C-482B-85E3-C59A3242DDEB/tmp/determine_basal_error_inputs.json tests
$ ./node_modules/.bin/mocha --inspect-brk -c tests/determine-basal-replay.test.js
```

And the replay test is waiting for you to attach a debugger. I use
Visual Studio to debug Javascript, but anything that understands JS
debugging protocols should work.

And at this point you can replay both JS and Swift implementations for
an input that causes an inconsistency and debug the issue.