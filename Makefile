.PHONY: format format-check lint-fix build test test-unit test-only test-ui coverage lint gate hooks-install system initialize-sims sim-status sim-shutdown sim-clean simulator-slots-check simulator-slots-sync simulator-slots-status

system:
	bash scripts/system-setup.sh

format:
	swiftformat .

# Check-only (no rewrite) — parity with the CI `lint` job's SwiftFormat step.
format-check:
	swiftformat --lint .

lint-fix:
	swiftlint --fix --quiet . && swiftlint lint --strict

build:
	bash scripts/build.sh

test:
	bash scripts/test.sh

test-unit:
	bash scripts/test-unit.sh

# Ad-hoc subset run. ONLY holds one or more -only-testing identifiers (space-separated).
#   make test-only ONLY="simple-recurring-budgetsTests/RatingPromptCoordinatorTests"
# Add --ui inside ONLY to include the UI target. See scripts/test-only.sh.
test-only:
	bash scripts/test-only.sh $(ONLY)

test-ui:
	bash scripts/test-ui.sh

# Line-coverage report from the latest unit .xcresult (run `make test-unit` first).
# Report-only — not a gate; nothing blocks on these numbers.
coverage:
	bash scripts/coverage.sh

lint:
	swiftlint lint --strict

# Full four-step gate (format -> lint-fix -> build -> test) in one command, logged
# to tmp/gate.log, stopping at the first failure. See scripts/gate.sh for why this
# single-command form exists (avoids the subshell/`; echo` permission prompt).
gate:
	bash scripts/gate.sh

hooks-install:
	lefthook install

initialize-sims:
	@ROOT="$(CURDIR)" bash -c 'source "$(CURDIR)/scripts/_sim_sandbox.sh"'

# -- Scoped simulator management (affects only this repo's device) --
# These targets operate on the single UDID stored in .build/sim/device.udid.
# Never use `pkill Simulator`, `killall Simulator`, or bare `simctl shutdown/erase all`
# — those commands affect every simulator on the machine.

_UDID_FILE := $(CURDIR)/.build/sim/device.udid

sim-status:
	@if [ -f "$(_UDID_FILE)" ]; then \
		udid=$$(cat "$(_UDID_FILE)"); \
		xcrun simctl list devices | grep "$$udid" || echo "(device $$udid not found in default set)"; \
	else \
		echo "(not initialized — run make initialize-sims)"; \
	fi

sim-shutdown:
	@if [ -f "$(_UDID_FILE)" ]; then \
		udid=$$(cat "$(_UDID_FILE)"); \
		xcrun simctl shutdown "$$udid" 2>/dev/null \
			&& echo "sim-sandbox: simulator $$udid shut down" \
			|| echo "sim-sandbox: simulator $$udid already shut down or not found"; \
	else \
		echo "sim-sandbox: not initialized"; \
	fi

sim-clean:
	@python3 scripts/sim_clean.py --slug-from-file "$(_UDID_FILE)" || true
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
