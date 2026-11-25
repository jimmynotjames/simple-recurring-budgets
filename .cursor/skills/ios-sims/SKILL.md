---
description: iOS simulator setup, management commands, UI_WORKERS concurrency tuning, two-pass test architecture, and AM/PM time workaround for this repo. Invoke when setting up a fresh clone, debugging simulator failures, adjusting parallelism, or writing UI tests that assert time strings.
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
SIMULATOR_NAME='iPad Pro 13-inch (M4)' make tests
```

## Management commands

These affect only this repo's simulator:

```bash
make initialize-sims  # create and boot this repo's simulator without building
make sim-status       # show this repo's simulator status
make sim-shutdown     # shut down this repo's simulator and its clones
make sim-clean        # shut down + delete this repo's simulator + remove .build/sim/
```

`make sim-clean` runs `scripts/sim_clean.py`, which deletes every device whose name contains this repo's unique slug (the base sim plus any orphaned `Clone N of …` from a parallel-testing crash). It cannot touch other repos' devices. A parallel UI run also deletes leftover clones before it starts (`sim_clean.py --clones-only`). Every command here and every test script holds the checkout's simulator lock (`.build/sim.lock`, `scripts/_sim_common.sh`), so two runs in one checkout wait for each other instead of fighting over the device.

Derived data and result bundles are per repo:

- `-derivedDataPath .build/sim/DerivedData`
- `-resultBundlePath .build/sim/results/<timestamp>.xcresult`

## UI pass concurrency: the simulator pool, UI_WORKERS and retries

`scripts/_sim_concurrency.sh` decides how many simulators a test run uses. The unit pass and `focused-tests` are always serial (one simulator). Full rules: `AGENTS.md` § "Simulator slots".

**Pool on** (the maintainer's machine, where `~/dev/simulator-slots` exists): each run builds first, then takes slots from a machine-wide pool shared with the maintainer's other repos. The UI pass asks for `UI_WORKERS` slots (default 2), gets what is free (at least 1), and runs that many clones. `SIMULATOR_SLOTS_FEWER=N` leaves N free slots unused; `SIMULATOR_SLOTS_TIMEOUT=S` gives up after S seconds (exit 75). `make simulator-slots-status` shows who holds what.

**Pool off** (everyone else, normal for contributors): the run prints a `simulator-slots: no shared pool` notice, takes nothing, and uses `UI_WORKERS` (default 1, serial):

| `UI_WORKERS` | UI pass flags | When to use |
| --- | --- | --- |
| unset or `1` | `-parallel-testing-enabled NO` (serial, 1 sim) | Lightest; the default without the pool. |
| `2` | `-parallel-testing-enabled YES -parallel-testing-worker-count 2 -maximum-parallel-testing-workers 2` | ≈16 GB Apple silicon with little else running. |
| `3` | same, with `3` | Only with headroom; RAM-heavy. |

Values outside 1–3 are clamped with a warning. The old names `SRB_SIM_MAX` and `SIMULATOR_WORKERS_WITHOUT_POOL` stop the run with "renamed to UI_WORKERS".

```bash
make tests                    # serial without the pool
UI_WORKERS=2 make ui-tests    # two clones
```

Agents: don't create the pool's directories or fetch its master. Tell the developer once that the pool wasn't found and what you used.

**Why RAM matters:** each booted simulator uses about 2–3 GB. On a ~16 GB machine with a browser open, 2 simulators fill the budget and a 3rd risks swap, across all repos, which is why the maintainer pools them.

**Retries:** `UI_RETRY_ON_FAILURE=auto|1|0`. `auto` (default) adds `-retry-tests-on-failure -test-iterations 2` when 2+ clones run, since the accessibility audits flake under CPU contention; `1` always retries (CI's shards); `0` never. A test that passed only on retry prints `PASSED-ON-RETRY: <test> <file:line> <message>` (on CI, a "UI test passed only on retry" warning). That is a flake: log it in `simple-recurring-budgetsUITests/FLAKY_TESTS.md`. A genuine failure fails both attempts and prints `TEST-FAILED:` lines.

## 24-hour time workaround

Sandbox simulators force 24h time globally. UI tests that assert AM/PM strings must add these to `app.launchArguments`:

```swift
app.launchArguments += ["-AppleICUForce24HourTime", "NO",
                        "-AppleICUForce12HourTimeFormat", "YES"]
```

## Two-pass XCUITest architecture

Pass 1 skips the UI test bundle (`-skip-testing:simple-recurring-budgetsUITests`). XCUITest needs the simulator to have hosted at least one real app lifecycle before its IPC socket is reliable; a freshly created per-repo sim hasn't, so the UI runner times out "while preparing to run tests".

`make tests` runs `scripts/unit-tests.sh` (pass 1, which writes the `.build/sim/warmed` sentinel) and then `scripts/ui-tests.sh` (pass 2), which runs the UI target's suites as selected by `scripts/ci/ui_shards.py` (`UI_SHARD=<name>` picks one of CI's shards): `AccessibilityAuditTests`, `UserJourneyTests`, `ClearAmountButtonUITests`, and `AllocationFirstTapUITests`. Apple does not support `import Testing` in unhosted XCUITest bundles; these suites use XCTestCase with `continueAfterFailure = false`. `testExample` and `testLaunchPerformance` are intentionally excluded from scripted runs.

A serial `make ui-tests` on an unwarmed device (no `warmed` sentinel; every boot clears it) runs one small unit suite on it first, so it works standalone. A parallel run skips that: its clones boot fresh.
