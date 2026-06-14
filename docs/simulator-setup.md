# Simulator setup and concurrency rationale

Reference material for the `SRB_SIM_MAX` simulator-concurrency knob. See `AGENTS.md §
Per-repo simulator sandbox` for the commands and quick rules.

## Reference machine

The default of `2` is tuned for an assumed baseline of roughly **16 GB RAM on an Apple-silicon
laptop** (e.g. a fanless M4 MacBook Air) running at most ~2 repo clones at once. These are
illustrative specs, not a requirement — adjust `SRB_SIM_MAX` for the machine actually running:
lower it on tighter RAM or when many repos run concurrently, raise it on a machine with more
memory/cores and active cooling.

## Why these defaults

- **RAM is usually the binding constraint.** On a ~16 GB machine with a browser + Mail open,
  2 simulators fills the budget; a 3rd risks swap. A fanless laptop also thermally throttles
  under sustained all-core load. Cross-repo parallelism is "free" — just run separate repos;
  each has its own sim with no machine-wide coordination.
- **The unit pass is always serial** (`-parallel-testing-enabled NO`, ignores `SRB_SIM_MAX`).
  Swift Testing already parallelizes the unit suite *in-process* on one sim, so extra clones
  add boot cost with no benefit. Running unit serially on the base device also warms the sim
  for the UI pass.
- **Flake retry:** when parallel (`>= 2`), the UI pass adds `-retry-tests-on-failure
  -test-iterations 2` (one retry). The accessibility-audit tests are timing-sensitive and
  occasionally flake under CPU contention; one retry absorbs this while a genuine failure
  still fails on both attempts. Serial runs (`=1`) are deterministic and add no retry.
- **The cap (≤ 3)** keeps this far from the old "dozens of clones across many agents →
  `Test crashed with signal kill`" teardown race.

## Clone-risk history

Clones of a per-repo device once timed out for the XCUITest pass ("while preparing to run
tests"), which is why parallel testing was previously disabled. This no longer reproduces
(validated June 2026, Xcode iPhone 17 runtime) as long as the unit pass warms the base sim
first. `SRB_SIM_MAX=1` remains the fallback if `2`/`3` flake.
