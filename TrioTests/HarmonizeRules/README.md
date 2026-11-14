# HarmonizeRules

Architectural lint rules for Trio, written as Swift Testing suites with
[Harmonize](https://github.com/perrystreetsoftware/Harmonize). Each rule parses the Swift sources
(rooted by `.harmonize.yaml` at the repository root, which also excludes the submodules and the
tools packages) and asserts on their structure: what a type conforms to, what a file imports, which
calls a function makes, what a project file lists. Nothing here compiles Trio, so the rules run on
Linux in about a minute, as the `harmonize` job in `.github/workflows/unit_tests.yml` does.

```sh
swift test --package-path TrioTests/HarmonizeRules
swift test --package-path TrioTests/HarmonizeRules --filter <RuleName>
```

The package sits beside the unit tests under `TrioTests/` but is part of neither `Trio.xcworkspace`
nor the `TrioTests` target, so Xcode never resolves swift-syntax for the app. It is not at the
repository root for the same reason `AlgorithmPackage` is not: a root `Package.swift` makes Xcode
open the package instead of the workspace.

## Writing a rule

One rule per file under `Tests/HarmonizeRulesTests/<Area>/`, named as the sentence it enforces
(`ViewsReadPublishedStateNotInjectedServices`). Scopes come from `TrioHarmonize.swift`. Every
assertion takes a `Rule` with a description, the rationale (what breaks when it is violated, with
the issue or commit that showed it), a fix hint and a bad and a good example; `RulesSelfExplain`
fails a rule file without one. A failing rule prints all of that at the offending line.

Violations that predate a rule go in its `baseline`, with `strict: true`, so Harmonize fails on a
baseline entry that no longer violates: a fix must also delete its line, and the list only shrinks.
Don't add to a baseline to get a new violation through; fix the code, not the rule.
