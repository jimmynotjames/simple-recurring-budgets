.PHONY: test lint format hooks-install system

system:
	bash scripts/system-setup.sh

test:
	bash scripts/test.sh

lint:
	swiftlint lint --strict

format:
	swiftformat .

hooks-install:
	lefthook install
