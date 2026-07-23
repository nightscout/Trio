#!/usr/bin/env python3
"""Regenerate ukf_python_reference.json — the L2 parity fixture.

Runs each trace through the reference Python `V4UKF` (the implementation the Boost benchmark scores
against) and records its `level_offline` (== max(smoothedResults, 39) — the same field the Swift
port writes to `.smoothed`) plus `rate_online`. `UkfPythonParityTests` asserts the Swift UKF
reproduces these.

Requires the Boost-AAPS-core smoothing suite on disk (not vendored here):
    backtesting/scripts/2026-07-ukf-smoothing/repeatable/smoothers.py  (+ its parent
    ukf_smoothing_backtest.py one directory up). Point SMOOTHERS_DIR at that `repeatable/` folder.

    SMOOTHERS_DIR=/path/to/2026-07-ukf-smoothing/repeatable \
        python3 generate_reference.py

Traces deliberately avoid the compression-low regime so both filters run the gate off, isolating the
shared numeric core. numpy only.
"""
import json
import math
import os
import sys

SMOOTHERS_DIR = os.environ.get("SMOOTHERS_DIR")
if not SMOOTHERS_DIR:
    sys.exit("set SMOOTHERS_DIR to the Boost repeatable/ folder containing smoothers.py")
sys.path.insert(0, SMOOTHERS_DIR)
from smoothers import V4UKF  # noqa: E402

BASE = 1_700_000_000_000
STEP = 5 * 60_000


def ts_newest_first(n):
    return [BASE - i * STEP for i in range(n)]


def run(values, ts=None):
    ts = ts or ts_newest_first(len(values))
    out = V4UKF().smooth(values, ts)
    return ts, [o["level_offline"] for o in out], [o["rate_online"] for o in out]


traces = {}


def add(name, values, ts=None):
    t, lo, ro = run(values, ts)
    traces[name] = dict(values=[float(v) for v in values], timestamps=t, level_offline=lo, rate_online=ro)


add("clean10", [101, 99, 100, 102, 98, 100, 101, 99, 100, 100])
add("rising8", [150, 140, 130, 120, 110, 100, 90, 80])
add("spike8", [100, 100, 100, 300, 100, 100, 100, 100])
add("det7", [120, 118, 122, 119, 121, 120, 118])
add("noisy30", [round(120 + 25 * math.sin(i * 0.45) + 4 * ((-1) ** i), 1) for i in range(30)])

# major-gap trace: cluster A (newest), a 120-min gap, cluster B (older) — two segments.
valsA, valsB = [100.0, 101.0, 99.0], [120.0, 119.0, 121.0]
tsA = [BASE - i * STEP for i in range(3)]
gapBase = BASE - (3 * 5 + 120) * 60_000
tsB = [gapBase - i * STEP for i in range(3)]
add("gap6", valsA + valsB, tsA + tsB)

# orphan trace: 2 leading points (newest) isolated by a 90-min gap from a 3-point segment. The two
# leading points join no segment (run < 3) — V4UKF pre-fills them to their floored raw value, so the
# Swift port must NOT leave them nil. Exercises the unprocessed-fill path.
orphanVals = [105.0, 103.0, 120.0, 119.0, 121.0]
orphanTs = [BASE, BASE - STEP, BASE - STEP - 90 * 60_000, BASE - STEP - 95 * 60_000, BASE - STEP - 100 * 60_000]
add("orphan5", orphanVals, orphanTs)

out_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ukf_python_reference.json")
json.dump(traces, open(out_path, "w"), indent=1)
print(f"wrote {len(traces)} traces -> {out_path}")
