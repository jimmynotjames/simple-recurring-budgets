---
description: iOS simulator setup, management commands, SRB_SIM_MAX concurrency tuning, two-pass test architecture, and AM/PM time workaround for this repo. Invoke when setting up a fresh clone, debugging simulator failures, adjusting parallelism, or writing UI tests that assert time strings.
---

# iOS Simulator reference

## Per-repo sandbox

Each clone of this repo gets its own dedicated simulator, identified by a unique device name derived from the repo's absolute path (e.g. `iPhone 17 [a1b2c3d4]`). The device lives in the default CoreSimulator device set (required by `xcodebuild`), but the unique name and UDID ensure no two clones ever share a simulator.

The sandbox is set up automatically by `scripts/_sim_sandbox.sh` (sourced by `scripts/_destination.sh`, in turn sourced by `scripts/build.sh` and `scripts/test.sh`). You do not need to manage the simulator manually for a normal build/test run.

**What happens on first run:**

1. `_sim_sandbox.sh` computes a unique device name from the repo path.
2. It resolves the device type and runtime for `SIMULATOR_NAME` via `scripts/resolve_sim_spec.py`.
3. It creates a new simulator in the default set with the unique name and boots it (~30–90 s one-time cost).
4. The UDID is stored in `.build/sim/device.udid` for use by `make sim-*` targets.
5. Subsequent runs find the booted simulator by UDID and reuse it (fast).

**Destination priority:**

1. **`SIMULATOR_UDID`** env var — pins a specific device and skips sandbox management entirely (escape hatch).
2. Any **already-booted** device whose name matches this repo's unique device name.
3. Any **existing but shutdown** device with that name — boots it.
4. **Creates a new device** with the unique name and boots it (first run only).

**Override the device name:**

```bash
SIMULATOR_NAME='iPhone 17' make build
SIMULATOR_NAME='iPad Pro 13-inch (M4)' make test
```

## Management commands

These targets affect **only this repo's** simulator device:

```bash
make initialize-sims  # create and boot this repo's simulator without building
make sim-status       # show this repo's simulator status
make sim-shutdown     # shut down this repo's simulator
make sim-clean        # shut down + delete this repo's simulator + remove .build/sim/
```

`make sim-clean` runs `scripts/sim_clean.py`, which finds every device whose name contains this repo's unique slug (the base sim plus any orphaned `Clone N of …` left behind by a parallel-testing crash) and deletes them all. It cannot touch other repos' devices.

**Derived data and result bundles** are scoped per repo:

- `-derivedDataPath .build/sim/DerivedData` — build cache stays per-clone.
- `-resultBundlePath .build/sim/results/<timestamp>.xcresult` — test results per run.

## SRB_SIM_MAX — UI pass concurrency

`SRB_SIM_MAX` (default `2`, range `1–3`, set by `scripts/_sim_concurrency.sh`) controls how many simulators the **UI pass** may run at once. The unit pass is always serial and ignores this knob.

| `SRB_SIM_MAX` | UI pass | When to use |
| --- | --- | --- |
| `1` | `-parallel-testing-enabled NO` (serial, 1 sim) | Lightest. Use if the UI pass flakes, or when several repos run at once. |
| `2` (default) | `-parallel-testing-enabled YES -maximum-concurrent-test-simulator-destinations 2` | Balanced default (≈16 GB Apple silicon, ≤ 2 repos at once). |
| `3` | …`-destinations 3` | Only with headroom — RAM-heavy. |

```bash
SRB_SIM_MAX=1 make test     # downshift: serial, lightest
SRB_SIM_MAX=3 make test-ui  # upshift: only if the machine is clear
```

**Why the defaults:** RAM is usually the binding constraint. On a ~16 GB machine with a browser + Mail open, 2 simulators fills the budget; a 3rd risks swap. A fanless laptop also thermally throttles under sustained all-core load. Cross-repo parallelism is "free" — each repo has its own sim with no machine-wide coordination.

**Flake retry:** when parallel (`>= 2`), the UI pass adds `-retry-tests-on-failure -test-iterations 2`. The accessibility-audit tests are timing-sensitive and occasionally flake under CPU contention; one retry absorbs that while a genuine failure still fails on both attempts. Serial runs (`= 1`) are deterministic and add no retry.

**Clone risk (historical):** clones of a per-repo device once timed out for the XCUITest pass ("while preparing to run tests"), which is why parallel testing was previously disabled. No longer reproduces (validated June 2026, Xcode iPhone 17 runtime) as long as the unit pass warms the base sim first. `SRB_SIM_MAX=1` remains the fallback if `2`/`3` flake.

## 24-hour time workaround

Sandbox simulators force 24h time globally. UI tests that assert AM/PM strings must add these to `app.launchArguments`:

```swift
app.launchArguments += ["-AppleICUForce24HourTime", "NO",
                        "-AppleICUForce12HourTimeFormat", "YES"]
```

## Two-pass XCUITest architecture

The UI test bundle is skipped in pass 1 (`-skip-testing:simple-recurring-budgetsUITests`). XCUITest requires the simulator to have hosted at least one real app lifecycle before its IPC socket is reliable. A freshly-created per-repo sim hasn't had this, so the UI runner times out "while preparing to run tests".

Pass 2 of `scripts/test.sh` runs `AccessibilityAuditTests`, `UserJourneyTests`, and `ClearAmountButtonUITests` with `-only-testing`. Apple does not support `import Testing` in unhosted XCUITest bundles; these suites use XCTestCase with `continueAfterFailure = false`. `testExample` and `testLaunchPerformance` are intentionally excluded from scripted runs.

Use `make initialize-sims && make build` to warm a fresh sim before running `make test-ui` standalone.
