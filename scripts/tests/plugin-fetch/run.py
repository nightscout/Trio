#!/usr/bin/env python3
"""Run the source-extracted PluginSource.fetch Combine contract on macOS."""
import argparse
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--source", type=pathlib.Path, default=ROOT / "Trio/Sources/APS/CGM/PluginSource.swift")
parser.add_argument("--full-timeout", action="store_true", help="Use the production five-minute timeout")
args = parser.parse_args()
source = args.source.read_text()
signature = "    func fetch(_: DispatchTimer?) -> AnyPublisher<[BloodGlucose], Never> {"
assert source.count(signature) == 1, "fetch signature changed; review this harness"
start = source.index(signature)
opening = source.index("{", start)
depth = 1
end = opening + 1
while depth:
    depth += (source[end] == "{") - (source[end] == "}")
    end += 1
method = source[start:end]
assert method.count(".timeout(60 * 5,") == 1, "timeout changed; review this harness"
if not args.full_timeout:
    method = method.replace(".timeout(60 * 5,", ".timeout(.milliseconds(40),")
# The operator expression is read from production, not copied into the tests.
# Only dependencies are substituted: an injected publisher and synthetic elements.
# Failure is generic to exercise the defensive replaceError; production uses Never.
preamble = """import Combine
import Foundation
import XCTest

typealias BloodGlucose = Int
struct DispatchTimer {}
final class FetchHarness<Failure: Error> {
    let processQueue = DispatchQueue(label: "PluginFetchContractTests")
    let upstream: AnyPublisher<[BloodGlucose], Failure>
    init<P: Publisher>(_ upstream: P) where P.Output == [BloodGlucose], P.Failure == Failure {
        self.upstream = upstream.eraseToAnyPublisher()
    }
    func fetchIfNeeded() -> AnyPublisher<[BloodGlucose], Failure> { upstream }
"""
swift = preamble + method + "\n}\n"
swift += "let timeoutWait: TimeInterval = " + ("310" if args.full_timeout else "3") + "\n"
swift += "let minimumTimeout: TimeInterval = " + ("299" if args.full_timeout else "0.035") + "\n"
swift += (pathlib.Path(__file__).parent / "tests.swift").read_text()
with tempfile.TemporaryDirectory(prefix="plugin-fetch-contract-") as directory:
    path = pathlib.Path(directory)
    tests = path / "Tests/PluginFetchTests"
    tests.mkdir(parents=True)
    (tests / "PluginFetchTests.swift").write_text(swift)
    (path / "Package.swift").write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "PluginFetchContract", platforms: [.macOS(.v13)],
    targets: [.testTarget(name: "PluginFetchTests")])
''')
    print("Testing source:", args.source, "full-timeout:", args.full_timeout, flush=True)
    raise SystemExit(subprocess.run(["swift", "test", "--package-path", str(path), "-Xswiftc", "-warnings-as-errors"]).returncode)
