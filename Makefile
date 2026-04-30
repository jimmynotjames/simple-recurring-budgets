.PHONY: format lint-fix build test lint hooks-install system

system:
	bash scripts/system-setup.sh

format:
	swiftformat .

lint-fix:
	swiftlint --fix --quiet . && swiftlint lint --strict

build:
	bash scripts/build.sh

test:
	bash scripts/test.sh

lint:
	swiftlint lint --strict

hooks-install:
	lefthook install
