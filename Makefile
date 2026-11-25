.PHONY: tool-versions-check format format-check lint-fix build tests unit-tests focused-tests ui-tests script-tests coverage lint gate hooks-install system initialize-sims sim-status sim-shutdown sim-clean simulator-slots-check simulator-slots-sync simulator-slots-status

system:
	bash scripts/system-setup.sh

tool-versions-check:
	bash scripts/check-tool-versions.sh

format:
	swiftformat .

# Check only; matches the CI `lint` job's SwiftFormat step.
format-check:
	swiftformat --lint .

lint-fix:
	swiftlint --fix --quiet . && swiftlint lint --strict

build:
	bash scripts/build.sh

# Opt-in: AGENTS.md §"Build and test". Named like CI's jobs (unit-tests, ui-tests, focused-tests).
# Unit then UI, as an automatic CI run does.
tests: unit-tests ui-tests

unit-tests:
	bash scripts/unit-tests.sh

# UI pass only; UI_SHARD=<name> runs one of CI's shards (scripts/ci/ui_shards.py), else all.
#   make ui-tests UI_SHARD=accessibility
ui-tests:
	bash scripts/ui-tests.sh

# make focused-tests ONLY=<target>/<Class>[/<test>] [ITERATIONS=3]; ONLY may hold several ids.
focused-tests:
	bash scripts/focused-tests.sh "$(ONLY)" $(ITERATIONS)

# Offline unit tests of the repo's CI/helper scripts; touch no simulator.
script-tests:
	python3 -m unittest discover -s scripts/tests

# Line-coverage report from the latest unit .xcresult (run `make unit-tests` first). Not a gate.
coverage:
	bash scripts/coverage.sh

lint:
	swiftlint lint --strict

# Four-step gate (format -> lint-fix -> build -> tests), logged to tmp/gate.log, stops
# at the first failure. Single-command form avoids permission prompts (see scripts/gate.sh).
gate:
	bash scripts/gate.sh

hooks-install:
	lefthook install

initialize-sims:
	@ROOT="$(CURDIR)" bash -c 'source "$(CURDIR)/scripts/_sim_sandbox.sh"'

# -- Scoped simulator management: only the UDID in .build/sim/device.udid --
# Never use `pkill Simulator`, `killall Simulator`, or bare `simctl shutdown/erase all`
# (they hit every simulator on the machine).

_UDID_FILE := $(CURDIR)/.build/sim/device.udid

sim-status:
	@if [ -f "$(_UDID_FILE)" ]; then \
		udid=$$(cat "$(_UDID_FILE)"); \
		xcrun simctl list devices | grep "$$udid" || echo "(device $$udid not found in default set)"; \
	else \
		echo "(not initialized — run make initialize-sims)"; \
	fi

# Both hold the checkout's simulator lock (scripts/_sim_common.sh), so they wait for a running test.
# sim-shutdown: every booted device with this checkout's slug (sandbox and clones).
sim-shutdown:
	@ROOT="$(CURDIR)" bash -c 'source "$(CURDIR)/scripts/_sim_common.sh" && sim_lock_acquire && python3 scripts/sim_clean.py --shutdown-only'

# sim-clean: delete every device and clone with this checkout's slug, then .build/sim (the lock
# file is outside it).
sim-clean:
	@ROOT="$(CURDIR)" bash -c 'source "$(CURDIR)/scripts/_sim_common.sh" && sim_lock_acquire && python3 scripts/sim_clean.py' || true
	rm -rf .build/sim
	@echo "sim-sandbox: .build/sim removed"

# -- Simulator slots ----------------------------------------------------------
# The machine-wide pool's master is ~/dev/simulator-slots (maintainer's machine only);
# scripts/simulator-slots is this repo's vendored copy (AGENTS.md §"Simulator slots").
# The check fails when the copy differs from the master's last commit and is skipped
# where the master doesn't exist; the copy's unit tests are offline and touch no simulator.
simulator-slots-check:
	python3 scripts/simulator-slots/simulator_slots.py sync-check --into scripts/simulator-slots
	python3 -m unittest discover -s scripts/simulator-slots/tests -q

# Maintainer only: refresh the copy from the master. Never edit the copy by hand.
simulator-slots-sync:
	python3 scripts/simulator-slots/simulator_slots.py sync --into scripts/simulator-slots

simulator-slots-status:
	@python3 scripts/simulator-slots/simulator_slots.py status
