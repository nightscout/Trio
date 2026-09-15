# Port Notes

As we're going through the port from Javascript to Swift, we'll use
this file to keep track of notes. Currently we outline our high level
plan and identify the risks that we have observed so far.

The good news is that from a preliminary inspection, the functions
that I've looked at in detail are pure functions, meaning that they
take inputs and produce an output without any side effects. All of the
state handling is on the native Swift side in Trio (at least so
far). Pure functions will be easier to test and less risky to port
incrementally.

## Plan

At the highest level, our plan is to first do a line-by-line port of
the Javascript implementation to build confidence that it works, then
to make it more "Swift-y" after we have confidence in the logic. Doing
a line-by-line port first makes it easier for us to debug, but we will
use more idiomatic Swift patterns where it makes sense.

Also, we plan to release this as a SPM so that other iOS / OpenAPS
systems can pick up this library, if it makes sense. But I'm open to
something different if people have strong opinions here.

Our plan is:

1. Port one function at a time. The functions, in order, are:
  - `makeProfile`
  - `iob`
  - `meal`
  - `autosense`
  - `determineBasal`

2. For each function, the process will be:
  - Write the code in Swift
  - Port the Javascript tests to Swift to confirm they work
  - Write new unit tests to get full code coverage (ideally)
  - Run the native function in Trio in a shadow mode, where we compute the results and simply compare with the Javascript implementation, logging any differences.

3. We should run each function in shadow mode for a week without any
inconsistencies before considering moving it to live execution. After
we move to live execution of a native function, we should continue to
run the Javascript implementation in shadow mode for 2 weeks to
continue to check for inconsistencies.

4. Once all functions are running natively and without inconsistencies
for two weeks, we can remove the Javascript implementation. After we
remove the Javascript implementation, we will consider the
line-by-line port to be complete, and can make decisions about any
further changes we'd like to make to the Swift implementation to
improve maintainability.

## Concurrency

Our goal is to make each of the functions pure functions, meaning that
they don't have any side effects and they're deterministic (given the
same inputs they'll produce the same outputs). There are some caveats
with floating point numbers and time (see [risks](#risks)), but so far
it looks like it'll be possible.

Having pure functions is a big benefit from a correctness perspective,
it makes testing easier and it makes it easier for people to use it
since they don't have to worry about ordering or sequencing
functions. Javascript has single-threaded semantics with an event
system, but we can ignore this if we can keep our functions pure.

## Risks

Here is a list of where we think bugs might crop up, so we're writing
them down to make sure we can keep an eye on it.

- **Javascript pass-by-reference.** Javascript uses pass-by-reference
    semantics, so if code modifies an input parameter then that value
    is changed. In our Swift port, we instead use pass-by-value
    semantics, trying to carefully navigate any visible changes that
    can come from modifications, which does happen in OpenAPS.

- **Javascript dynamic properties.** Javascript can add properties on
    the fly, which is hard to get right. Our plan is to use static
    typing and make sure that we include properties that Javascript
    would generate dynamically, but this is a potential source of
    inconsistencies.

- **Javascript type switching.** There is at least one property
     (Profile.target_bg) where the Javascript implementation uses
     boolean `false` as a proxy for Optional none, where the property
     is a Number. I have a property annotation to deal with it, but
     it's something we'll want to get rid of after the port. The Swift
     implementation does _not_ use this behavior, we try to constrain
     it to the serialization routines to maintain JSON compatibility.

- **var now = new Date();** There are several places where the
    Javascript implementation gets the current time using `new
    Date()`. This style of time management can lead to issues if we're
    right at a boundary when it runs. Since this is how the Javascript
    is implemented we use it too, but we'll want to fix that soon.

- **Double vs Decimal.** In Swift we use the Decimal class for
    floating point computation. However, our goal is to match the
    current Javascript implementation, which uses Double, so we need
    to keep an eye on this because the two can be different.

- **Trio-specific inputs.** There are places where the Trio
    implementation it a little different than what the Javascript
    expects. An example is `BasalProfileEntry` doesn't have an `i`
    property, so the sorting function for these entries in Javascript
    is a no-op, so we excluded it.

- **Preferences -> Profile.** The Javascript implementation copies
    input properties into the Profile if they exist. In Trio, in
    Javascript we copy the Preferences to the input for this
    purpose. In this library, we do this copy by hard-coding all
    properties that have the same CodingKeys, but this was a manual
    process and something we need to remember to change if either
    Profile or Preferences changes. We'll fix this with v2, but for
    now this was the cleanest way I could come up with for handling it
    in Swift. See the Profile extension that implements `update` for
    more details.

## Todos

So far, the biggest cleanup items are to see if we can avoid
reproducing the logic that mutates inputs. There are a few TODOs in
the code to mark these to evaluate later, but for now we'll just
produce the same JSON that the Javascript library does.

The next biggest change is to be consistent with time. There are a
bunch of places that the Javascript uses the current time of day, we
should pass in one time to both algorithms so that they produce
consistent results.

In terms of enhancements after the port, here are some issues that we
created to track some cleanup that we should do:
- [Refactor outUnits in Profile](https://github.com/nightscout/Trio-dev/issues/289)
- [Allow 0 basal rates](https://github.com/nightscout/Trio-dev/issues/288)
- [Use insulin-based curves](https://github.com/nightscout/Trio-dev/issues/287)

## Sources

For our port, we're using:

- trio-oref (tcd branch) git SHA: ade267da32435df5e8edca5738a24b687f8ba001

- Trio-dev (core-data-sync-trio branch) git SHA: dc43b0ae8fb106d7b30cf97e29d8a931efbf1339