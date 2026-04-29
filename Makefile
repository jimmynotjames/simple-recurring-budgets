.PHONY: test lint format hooks-install

test:
	bash scripts/test.sh

lint:
	swiftlint lint --strict

format:
	swiftformat .

hooks-install:
	lefthook install
