.PHONY: tool-versions-check format format-check lint-fix format-changed lint-changed build tests unit-tests focused-tests ui-tests script-tests coverage lint gate hooks-install system initialize-sims sim-udid sim-show sim-run sim-status sim-shutdown sim-clean simulator-slots-check simulator-slots-sync simulator-slots-status

system:
	bash scripts/system-setup.sh

tool-versions-check:
	bash scripts/check-tool-versions.sh

format:
	bash scripts/swiftformat.sh

# Check only; matches the CI `lint` job's SwiftFormat step.
format-check:
	bash scripts/swiftformat.sh --lint

lint-fix:
	swiftlint --fix --quiet . && swiftlint lint --strict

# Format only the Swift files this branch changed (scripts/changed-swift-files.sh). The gate's
# form; `format` stays for a repo-wide pass by hand.
format-changed:
	@files=$$(bash scripts/changed-swift-files.sh); \
	if [ -z "$$files" ]; then echo "format-changed: no changed Swift files"; else \
	  echo "$$files" | tr '\n' ' ' | xargs bash scripts/swiftformat.sh; fi

# Autocorrect then strict-lint only the Swift files this branch changed.
lint-changed:
	@files=$$(bash scripts/changed-swift-files.sh); \
	if [ -z "$$files" ]; then echo "lint-changed: no changed Swift files"; else \
	  echo "$$files" | tr '\n' ' ' | xargs swiftlint --fix --quiet && \
	  echo "$$files" | tr '\n' ' ' | xargs swiftlint lint --strict --quiet; fi

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

# The gate (scripts/gate.sh has the steps): format and lint on changed files, tooling tests,
# compile. No simulator; the app suites run in CI. Logged to tmp/gate.log, stops at the first
# failure. Single-command form avoids permission prompts.
gate:
	bash scripts/gate.sh

hooks-install:
	lefthook install

initialize-sims:
	@bash scripts/sim.sh init

sim-udid:
	@bash scripts/sim.sh udid

sim-show:
	@bash scripts/sim.sh show

sim-run:
	@bash scripts/sim.sh run

sim-status:
	@bash scripts/sim.sh status

sim-shutdown:
	@bash scripts/sim.sh shutdown

sim-clean:
	@bash scripts/sim.sh clean

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
