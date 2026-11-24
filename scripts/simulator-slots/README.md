# simulator-slots

A machine-wide cap on how many iOS simulators run tests at once, shared by every repo that opts
in. Each opted-in repo can run its own simulator; the pool decides how many of them may be running
tests at the same time.

## Model

- **Slot:** one simulator actively running tests. The pool size is the `max` file in the state
  directory (default 2). A booted simulator that is not running tests holds no slot.
- **Holding slots:** `simulator_slots.py hold` flocks free slots and releases them when the
  process it watches exits. The kernel drops a flock when its holder dies, so a crashed run never
  leaves a slot taken.
- **Partial grants:** a run asks for up to N slots and starts with whatever is free, at least 1. It
  waits only when none are free.
- **Run log:** every run appends to `runs.log`: slots wanted and granted, time spent waiting, time
  held, exit code, and swap before and after.

State lives outside every repo, in `~/.local/state/simulator-slots/`: `protocol`, `max`,
`slot-N.lock`, `runs.log`.

## Knobs

| Variable | Effect |
| --- | --- |
| `SIMULATOR_SLOTS_FEWER=N` | This run leaves N of the free slots unused. Use it when you need headroom for your own simulator or other heavy work. |
| `SIMULATOR_SLOTS_TIMEOUT=S` | Give up (exit 75) after waiting S seconds. |
| `max` file | Pool size; edit it to change the cap for every repo at once. |

`simulator_slots.py status` shows the pool, each slot's holder, every booted simulator (idle or
in use), and the last ten runs.

## Opting a repo in

1. Copy this directory into the repo with `simulator_slots.py sync --into <repo>/<dir>`. The
   `.git` directory is not copied.
2. Wrap each test run.
   - **Bash:** source `simulator_slots.sh` with `SIMULATOR_SLOTS_HOME` set, then call
     `simulator_slots_hold WANT LABEL ROOT [UDID] [OWNS]` after building and before testing.
     `OWNS` is text in the names of the run's devices (for example a checkout tag), so `status`
     shows them in use.
   - **Other languages:** start `hold --watch-pid <own pid>` with a pipe and read its one line,
     `<granted> <run-id>`.
3. Pass the granted count to xcodebuild as its parallel worker count.
4. Add `simulator_slots.py sync-check --into <dir>` to the repo's gate. It fails when the copy
   differs from this master's last commit (uncommitted edits here don't count), and is skipped on
   machines without the master.
5. Run this directory's tests in the repo's tooling tests:
   `python3 -m unittest discover -s <dir>/tests`.

## Changing the tool

1. Edit and test here first.
2. Bump `VERSION`.
3. If the state layout or the locking changes, bump `PROTOCOL` in `simulator_slots.py`. Copies
   speaking another protocol refuse to run instead of sharing a pool they would miscount.
4. Sync each opted-in repo; their gates fail until you do.
