---
description: iOS simulator setup, management commands, SRB_SIM_MAX concurrency tuning, two-pass test architecture, and AM/PM time workaround for this repo. Invoke when setting up a fresh clone, debugging simulator failures, adjusting parallelism, or writing UI tests that assert time strings.
---

# iOS Simulator reference

## Per-repo sandbox

Each clone gets its own simulator, named from the repo's absolute path (e.g. `iPhone 17 [a1b2c3d4]`). The device lives in the default CoreSimulator device set (required by `xcodebuild`); the unique name and UDID keep clones from sharing a simulator.

The sandbox is set up automatically by `scripts/_sim_sandbox.sh` (sourced by `scripts/_destination.sh`, in turn sourced by `scripts/build.sh` and the test scripts). You do not need to manage the simulator manually for a normal build/test run.

First run:

1. `_sim_sandbox.sh` computes a unique device name from the repo path.
2. It resolves the device type and runtime for `SIMULATOR_NAME` via `scripts/resolve_sim_spec.py`.
3. It creates the simulator in the default set and boots it (~30–90 s, one time).
4. The UDID is stored in `.build/sim/device.udid` for `make sim-*` targets.
5. Later runs find the booted simulator by UDID and reuse it.

Destination priority:

1. `SIMULATOR_UDID` env var: pins a specific device and skips sandbox management (escape hatch).
2. Any already-booted device matching this repo's unique device name.
3. Any existing shutdown device with that name: boots it.
4. Creates a new device with the unique name and boots it (first run only).

Override the device name:

```bash
SIMULATOR_NAME='iPhone 17' make build
SIMULATOR_NAME='iPad Pro 13-inch (M4)' make test
```

## Management commands

These affect only this repo's simulator:

```bash
make initialize-sims  # create and boot this repo's simulator without building
make sim-status       # show this repo's simulator status
make sim-shutdown     # shut down this repo's simulator
make sim-clean        # shut down + delete this repo's simulator + remove .build/sim/
```

`make sim-clean` runs `scripts/sim_clean.py`, which deletes every device whose name contains this repo's unique slug (the base sim plus any orphaned `Clone N of …` from a parallel-testing crash). It cannot touch other repos' devices.

Derived data and result bundles are per repo:

- `-derivedDataPath .build/sim/DerivedData`
- `-resultBundlePath .build/sim/results/<timestamp>.xcresult`

## UI pass concurrency: the simulator pool and SRB_SIM_MAX

`scripts/_sim_concurrency.sh` decides how many simulators a test run uses. The unit pass and `test-only` are always serial (one simulator). Full rules: `AGENTS.md` § "Simulator slots".

**Pool on** (the maintainer's machine, where `~/dev/simulator-slots` exists): each run builds first, then takes slots from a machine-wide pool shared with the maintainer's other repos. The UI pass asks for `SRB_SIM_MAX` slots (default 2), gets what is free (at least 1), and runs that many clones. `SIMULATOR_SLOTS_FEWER=N` leaves N free slots unused; `SIMULATOR_SLOTS_TIMEOUT=S` gives up after S seconds (exit 75). `make simulator-slots-status` shows who holds what.

**Pool off** (everyone else — normal for contributors): the run prints a `simulator-slots: no shared pool at …` notice and takes nothing. Concurrency is your call:

| `SRB_SIM_MAX` | UI pass flags | When to use |
| --- | --- | --- |
| unset | none — the scheme decides (it allows parallel clones) | Your own setup is in charge. |
| `1` | `-parallel-testing-enabled NO` (serial, 1 sim) | Lightest. Use if the UI pass flakes, or when other simulators are busy. |
| `2` | `-parallel-testing-enabled YES -parallel-testing-worker-count 2 -maximum-parallel-testing-workers 2` | ≈16 GB Apple silicon with little else running. |
| `3` | same, with `3` | Only with headroom — RAM-heavy. |

```bash
SRB_SIM_MAX=1 make test     # serial, lightest
SRB_SIM_MAX=2 make test-ui  # two clones
```

Agents: don't create the pool's directories or fetch its master. Pick a value (or ask), and tell the developer once that the pool wasn't found and what you used.

**Why RAM matters:** each booted simulator uses about 2–3 GB. On a ~16 GB machine with a browser open, 2 simulators fill the budget and a 3rd risks swap — across all repos, which is why the maintainer pools them.

Flake retry: when parallel (`>= 2`), the UI pass adds `-retry-tests-on-failure -test-iterations 2`. The accessibility-audit tests are timing-sensitive and occasionally flake under CPU contention; one retry absorbs that, and a genuine failure still fails both attempts. Serial runs (`= 1`) are deterministic and add no retry.

Clone risk (historical): clones of a per-repo device once timed out for the XCUITest pass ("while preparing to run tests"), so parallel testing was disabled. It no longer reproduces (validated June 2026, Xcode iPhone 17 runtime) as long as the unit pass warms the base sim first. `SRB_SIM_MAX=1` remains the fallback if `2`/`3` flake.

## 24-hour time workaround

Sandbox simulators force 24h time globally. UI tests that assert AM/PM strings must add these to `app.launchArguments`:

```swift
app.launchArguments += ["-AppleICUForce24HourTime", "NO",
                        "-AppleICUForce12HourTimeFormat", "YES"]
```

## Two-pass XCUITest architecture

Pass 1 skips the UI test bundle (`-skip-testing:simple-recurring-budgetsUITests`). XCUITest needs the simulator to have hosted at least one real app lifecycle before its IPC socket is reliable; a freshly created per-repo sim hasn't, so the UI runner times out "while preparing to run tests".

`make test` runs `scripts/test-unit.sh` (pass 1, which writes the `.build/sim/warmed` sentinel) and then `scripts/test-ui.sh` (pass 2), which runs `AccessibilityAuditTests`, `UserJourneyTests`, `ClearAmountButtonUITests`, and `AllocationFirstTapUITests` with `-only-testing`. Apple does not support `import Testing` in unhosted XCUITest bundles; these suites use XCTestCase with `continueAfterFailure = false`. `testExample` and `testLaunchPerformance` are intentionally excluded from scripted runs.

Run `make test-unit` once on a fresh sim before running `make test-ui` standalone; `test-ui.sh` refuses to run without the `warmed` sentinel.
