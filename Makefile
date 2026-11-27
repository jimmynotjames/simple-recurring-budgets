.PHONY: tool-versions-check format format-check lint-fix format-changed lint-changed build tests unit-tests focused-tests ui-tests script-tests i18n-check i18n-sync i18n-sync-check uitest-check coverage lint gate hooks-install system initialize-sims sim-udid sim-show sim-run sim-status sim-shutdown sim-clean simulator-slots-check simulator-slots-sync simulator-slots-status

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

# Offline unit tests of the repo's CI/helper scripts and the simulator-slots copy; touch no
# simulator. See scripts/script-tests.sh.
script-tests:
	bash scripts/script-tests.sh

# -- Localization -------------------------------------------------------------
# Repo-wide on purpose: check_translations validates the catalog, check_source_strings enforces
# a repo invariant (no unkeyed user-facing copy), and untranslated_copies catches English left in
# a translated slot. All take under a second.
i18n-check:
	python3 scripts/check_translations.py
	python3 scripts/check_source_strings.py
	python3 scripts/translate_audit/untranslated_copies.py
	python3 scripts/translate_audit/distinct_pairs.py
	python3 scripts/screenshot_content/check_content.py

# Merge the last `make build`'s extracted strings into the catalog, as a build in Xcode does:
# Swift `comment:` changes, new keys, and `stale` for keys gone from Swift. Needs that build.
i18n-sync:
	python3 scripts/translate_catalog/sync_catalog.py

# The gate's form: fails when i18n-sync would change the catalog.
i18n-sync-check:
	python3 scripts/translate_catalog/sync_catalog.py --check

# Static checks; the UI tests themselves run in CI (AGENTS.md §"Build and test").
uitest-check:
	python3 scripts/check_ui_test_keyboard.py

# Line-coverage report from the latest unit .xcresult (run `make unit-tests` first). Not a gate.
coverage:
	bash scripts/coverage.sh

lint:
	swiftlint lint --strict

# The gate (scripts/gate.sh has the steps): format and lint on changed files, string checks,
# tooling tests, compile, catalog sync check. No simulator; the app suites run in CI. Logged to tmp/gate.log, stops at the first
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
# where the master doesn't exist. The copy's unit tests run in `make script-tests`.
simulator-slots-check:
	python3 scripts/simulator-slots/simulator_slots.py sync-check --into scripts/simulator-slots

# Maintainer only: refresh the copy from the master. Never edit the copy by hand.
simulator-slots-sync:
	python3 scripts/simulator-slots/simulator_slots.py sync --into scripts/simulator-slots

simulator-slots-status:
	@python3 scripts/simulator-slots/simulator_slots.py status
