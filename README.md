# Wren — Daily Expense Tracker

> A native iOS / iPadOS app for staying on top of small, recurring everyday spending — built with SwiftUI, SwiftData, and CloudKit sync.

[![Download on the App Store](https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/en-us?size=250x83)](https://apps.apple.com/us/app/wren-daily-expense-tracker/id6774680765)
[![CI](https://github.com/jimmynotjames/simple-recurring-budgets/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/jimmynotjames/simple-recurring-budgets/actions/workflows/ci.yml)



## About

This project was my attempt to learn agentic programming. All but two lines of code were produced by agents, along with lots of human judgment and discernment (Me: iOS developer for 15+ years). See retrospective doc below for more details about AI programming. 

**Thoughts on agentic programming:** `[RETROSPECTIVE.md](RETROSPECTIVE.md)` 

**Product and Design thinking:** `[docs/main-prd.md,](docs/main-prd.md)` ****`[docs/ux-design-brief.md](docs/ux-design-brief.md)` 

**Technical Design:**  `[ARCHITECTURE.md](ARCHITECTURE.md)`**,** `[docs/tech-design-doc.md](docs/tech-design-doc.md)`

**Analytics Design:** `[docs/analytics-spec.md](docs/analytics-spec.md)`

---



## Screenshots


| Budgets | Add Expense | Budget Detail | Add Budget | Settings |
| ------- | ----------- | ------------- | ---------- | -------- |
|         |             |               |            |          |


---



## Status

- **The app has released in the Apple App Store.** [Get Wren on the App Store](https://apps.apple.com/us/app/wren-daily-expense-tracker/id6774680765). See [RELEASES.md](RELEASES.md).
- Schema is `SchemaV1`, evolved in place (no migration stages yet) — see `docs/tech-design-doc.md` §3.3.
- Versioned product/technical docs and an OpenSpec change history are tracked in-repo.

---



## Features

> Full feature set in the agent-readable doc: `[docs/product-features-planning.md](docs/product-features-planning.md)`.

- 💸 **Fast expense logging** — add an expense in as few taps as possible; recents-assisted entry.
- 📊 **Recurring budgets** — daily, weekly, biweekly, monthly, or a fixed-window "Specific Dates" trip budget.
- 🔁 **Carry-over** — a per-budget signed surplus/deficit that tells you if you're ahead or behind over time (toggleable).
- ⏸️ **Pause / resume** budgets, plus distinct **Reset Carry-Over / Reset Budget / Delete Budget** actions.
- 💱 **Per-budget currency** (ISO 4217) with locale-aware formatting; no FX conversion though.
- ☁️ **CloudKit sync** across the user's devices; settings sync via iCloud key-value store.
- 🌗 **Dark Mode**, **Dynamic Type**, and **VoiceOver** support throughout.
- 🌍 **All current 49 App Store storefront locales**.
- 🔒 **Privacy-first analytics** — consent-gated, no PII, off by default in strict-opt-in jurisdictions.

---



## Tech stack


| Layer                           | Choice                                                                                       |
| ------------------------------- | -------------------------------------------------------------------------------------------- |
| **Language**                    | Swift 6.0 — strict concurrency, default `@MainActor` isolation                               |
| **UI**                          | 100% SwiftUI                                                                                 |
| **Persistence**                 | SwiftData                                                                                    |
| **Sync**                        | CloudKit database app settings syncing                                                       |
| **Min OS**                      | iOS / iPadOS 26.5+                                                                           |
| **Targets**                     | iPhone + iPad; eventaully macOS                                                              |
| **Analytics**                   | Mixpanel + `OSLog`                                                                           |
| **Unit tests**                  | Swift Testing (`@Test` / `#expect`)                                                          |
| **UI tests**                    | XCTest / XCUITest + `performAccessibilityAudit()`                                            |
| **i18n**                        | Xcode String Catalogs (`.xcstrings`) + a custom culturally-sensitive AI translation pipeline |
| **Local gates**                 | Lefthook · SwiftLint · SwiftFormat · gitleaks                                                |
| **CI/CD**                       | GitHub Actions                                                                               |
| **Release automation**          | Fastlane for TestFlight, App Store metadata, screenshots, etc.                               |
| **Spec-Driven Development**     | OpenSpec for product-level changes                                                           |
| **Non-coding workflows**        | Bash scripts · Python · Makefile                                                             |
| **AI Agents for Coding**        | Claude Code, Cursor, Xcode                                                                   |
| **AI Agents for Visual Design** | Claude Code, Cursor, Xcode, Figma AI, Claude Design (Research Preview)                       |


---



## Project structure

```
simple-recurring-budgets/         # App target (~102 Swift files)
├── App/                          # Entry point, Router, AppStartup, container creation
├── Domain/                       # Pure budget math: PeriodCalculator, BudgetCalculator, BudgetLifecycleService
├── Models/                       # SwiftData @Model entities: Budget, ExpenseItem, AllocationChange, LifecycleEvent
├── Views/                        # SwiftUI screens: BudgetList, BudgetDetail, BudgetForm, ExpenseForm, Settings, Shared
├── Settings/                     # AppSettings (iCloud key-value backed preferences)
├── Sync/                         # SyncStatus environment value (CloudKit account/backing state)
├── Formatting/                   # Currency / number formatting helpers
├── Logging/                      # OSLog category loggers
├── RatingPrompt/                 # App Store rating-prompt eligibility + coordinator
└── Resources/                    # Assets.xcassets, AppIcon.icon, Localizable.xcstrings

simple-recurring-budgetsTests/    # Swift Testing unit suite (~82 files)
simple-recurring-budgetsUITests/  # XCUITest user-journey + accessibility-audit suites, screen objects, screenshot seeds
scripts/                          # ~49 Python/shell scripts: translation pipelines, sim helpers, gates
fastlane/                         # Lanes + per-storefront metadata for 49 locales
openspec/                         # Spec-driven change workflow
docs/                             # PRD, tech design, UX brief, feature planning, audits
```



## Dependencies

Deliberately minimal — Apple-first policy, with Mixpanel as the **only** direct third-party runtime dependency (Swift Package Manager, Xcode-project-managed).


| Package                                                                      | Why               | Notes                                    |
| ---------------------------------------------------------------------------- | ----------------- | ---------------------------------------- |
| `[mixpanel-swift](https://github.com/mixpanel/mixpanel-swift)`               | Product analytics | Direct; lazy-init, consent-gated, no PII |
| `[mixpanel-swift-common](https://github.com/mixpanel/mixpanel-swift-common)` | —                 | Transitive (via Mixpanel)                |
| `[json-logic-swift](https://github.com/advantagefse/json-logic-swift)`       | —                 | Transitive (via Mixpanel)                |


Everything else is **Apple frameworks**: SwiftUI, SwiftData, CloudKit, Foundation, `OSLog`, StoreKit (rating prompt), and the String Catalog toolchain. SPM bumps are manual (no `Package.swift`; Dependabot tracks GitHub Actions only).

---



## AI Agent Configs

- **Mirrored Cursor / Claude Code setup.** Hand-authored commands and skills are kept in sync as duplicate copies — `.claude/commands/*.md` ↔ `.cursor/commands/*.md`, `.claude/skills/<name>/SKILL.md` ↔ `.cursor/skills/<name>/SKILL.md` — so either tool can drive the same workflow. Some cross-cutting rules (concurrency, build/test procedure, per-repo state locality) are also mirrored into `.cursor/rules/*.mdc` so Cursor gets the same guardrails Claude Code reads from `AGENTS.md`. `AGENTS.md` is the canonical source; the Cursor copies are kept in sync with it, not the other way around.
- **Custom skills** (project-specific, not generic framework reference):
  - `[create-pr](.claude/skills/create-pr/SKILL.md)` — review, gate, and open a PR from already-written changes
  - `[create-pr-for-issue](.claude/commands/create-pr-for-issue.md)` — turn a GitHub issue into a reviewed, gated PR
  - `[merge-pr](.claude/commands/merge-pr.md)` — squash-merge a reviewed PR and close its linked issue
  - `[translate-new-strings](.claude/skills/translate-new-strings/SKILL.md)` — translate new/stale in-app string keys to 49 locales
  - `[audit-translations](.claude/skills/audit-translations/SKILL.md)` — quality-audit existing translations (tone, truncation, accuracy)
  - `[appstore-translate-metadata](.claude/skills/appstore-translate-metadata/SKILL.md)` — transcreate the App Store listing into 49 storefronts
  - `[appstore-generate-screenshot-seeding](.claude/skills/appstore-generate-screenshot-seeding/SKILL.md)` — generate culturally-tuned per-locale screenshot demo data
  - `[appstore-generate-push-screenshots](.claude/skills/appstore-generate-push-screenshots/SKILL.md)` — capture and upload localized App Store screenshots
  - `[appstore-push-testflight-build](.claude/skills/appstore-push-testflight-build/SKILL.md)` — cut and ship a TestFlight build end-to-end
  - `[appstore-prepare-for-release](.claude/skills/appstore-prepare-for-release/SKILL.md)` — collaborative, resumable driver for the App Store release checklist
  - `[appstore-push-release-build](.claude/skills/appstore-push-release-build/SKILL.md)` — bump the version and cut the App Store release-candidate build via TestFlight
  - `[cloudkit-deploy-schema](.claude/skills/cloudkit-deploy-schema/SKILL.md)` — safely deploy the CloudKit schema from Development to Production, with mandatory audit/confirmation gates
  - `[mixpanel-build-boards](.claude/skills/mixpanel-build-boards/SKILL.md)` — build/reconcile Mixpanel dashboards against `docs/analytics-spec.md`
  - `[ios-sims](.claude/skills/ios-sims/SKILL.md)` — simulator setup, concurrency tuning, two-pass test architecture reference
  - `[translation-accessibility-size-check](.claude/skills/translation-accessibility-size-check/SKILL.md)` — ad-hoc visual check for truncation/RTL at large Dynamic Type
- **Other configuration.** `.claude/agents/` pins model-specific subagents for parallel per-locale fan-out (Haiku for translation, Opus for audit/glossary/content generation). `.claude/settings.json` allowlists the deterministic pipeline scripts and gates so agents run the translation/metadata/screenshot pipelines without permission prompts, plus a pre-tool-use hook enforcing Bash hygiene. The `openspec-`* skills/commands are packaged by [OpenSpec](https://github.com/Fission-AI/OpenSpec) itself and regenerate on update — behavioral overrides for that workflow live in `openspec/config.yaml` and `AGENTS.md` instead of the generated files. A further set of generic Apple-platform reference skills (SwiftData, CloudKit, App Intents, accessibility, localization, Swift concurrency/testing, SwiftUI patterns, etc.) round out the toolbox but aren't project-specific.



## Localization & accessibility

- **49 App Store storefront locales**, keyed in `Localizable.xcstrings` with translator comments and locale-aware number/currency/date formatting (`Decimal.FormatStyle.Currency`, CLDR plurals).
- **Custom AI translation pipeline** (`scripts/translate_catalog/`): `extract → translate → merge → validate`, with parallel per-locale model subagents and a `validate.py` gate (format-specifier parity, missing-key, RTL checks) enforced on pre-push and in CI.
- A **separate metadata pipeline** (`scripts/translate_metadata/`) transcreates the App Store listing into all 49 storefronts.
- **Accessibility** is a per-change requirement, not a phase: Dynamic Type (semantic styles, `@ScaledMetric`), VoiceOver (composed labels, header rotor traits, destructive-action hints, `swipeActions` ↔ `accessibilityAction` pairing), and Dark Mode (named asset colors, no literals). Verified by 30 `performAccessibilityAudit()` tests.



## Testing

- **Unit:** Swift Testing, in-memory `ModelContainer` for isolation; budget math lives in pure `Domain/` services with no UI dependency.
- **UI:** two XCUITest suites driven by five screen objects —
  - `UserJourneyTests` — 15 end-to-end flows (create/edit/delete budget, add/edit/delete expense, pause/resume, reorder, settings round-trip, period-chip behavior).
  - `AccessibilityAuditTests` — 30 audits across every major screen.
- **Two-pass runner** (`scripts/test.sh`): unit tests first to warm the simulator, then the UI passes. `make test-ui` runs only the UI pass.

```bash
make test       # full unit + UI suite
make test-ui    # UI suite only
```



## Tooling, CI & release

- **Local gates (Lefthook):** pre-commit runs SwiftFormat, SwiftLint `--fix` + strict, a large-file guard, and gitleaks; pre-push does a bare `xcodebuild build`.
- **Four-step dev gate:** `make format` → `make lint-fix` → `make build` → `make test`.
- **CI (GitHub Actions,** `[ci.yml](.github/workflows/ci.yml)`**):** `lint`, `secrets` (gitleaks full-history), `i18n-gates` (translation/source/metadata checks), `build`, and `unit-tests` — version-pinned to match local installs. Full UI suite runs on-demand via `/test-full`.
- **Release (Fastlane):** lanes for `beta` (TestFlight), `release` (App Store), `push_metadata`, and `screenshots`, all guarded by a pre-build secrets check (`scripts/verify_release_secrets.sh`). App Store Connect API key auth; secrets live outside the repo.
- **Spec-driven workflow:** [OpenSpec](https://github.com/Fission-AI/OpenSpec) change proposals under `openspec/`.

---



## Getting started

You can build and run on the iOS Simulator with **no secrets and no Apple Developer account**:

```bash
make system    # one-time: installs Lefthook, SwiftLint, SwiftFormat, gitleaks; checks Xcode + Python
make build     # Debug → Simulator build using committed placeholder config
make test      # boots the repo's simulator and runs the full suite
```

Full setup — including the two-tier flow (Simulator-only vs. shipping/forking for distribution), secrets configuration, and Fastlane — is in `[CONTRIBUTING.md](CONTRIBUTING.md)`.

## Docs Index


| Document                                                                 | Description                                              |
| ------------------------------------------------------------------------ | -------------------------------------------------------- |
| `[RETROSPECTIVE.md](RETROSPECTIVE.md)`                                   | Essay on building this app with agentic AI               |
| `[ARCHITECTURE.md](ARCHITECTURE.md)`                                     | High-level, human-readable engineering map               |
| `[docs/main-prd.md](docs/main-prd.md)`                                   | Product requirements and global constraints              |
| `[docs/ux-design-brief.md](docs/ux-design-brief.md)`                     | UX guidelines                                            |
| `[docs/product-features-planning.md](docs/product-features-planning.md)` | Feature IDs and acceptance criteria                      |
| `[docs/tech-design-doc.md](docs/tech-design-doc.md)`                     | Technical architecture, persistence/sync, tooling        |
| `[docs/analytics-spec.md](docs/analytics-spec.md)`                       | Analytics events, consent, and no-PII rules              |
| `[docs/audits/](docs/audits)`                                            | Periodic architecture / code / localization drift audits |
| `[AGENTS.md](AGENTS.md)`                                                 | Canonical instructions for AI coding agents in this repo |


---



## License, trademarks & contributing

- **License.** Source code is licensed under the **Apache License 2.0** — see `[LICENSE](LICENSE)`.
- **Trademarks.** The **Wren** name and app icon are trademarks of Jimmy Ho and are **not** covered by the code license. Forks that distribute an app must replace the name, icon, and App Store marketing assets before shipping — see `[TRADEMARK.md](TRADEMARK.md)`.
- **Contributing.** See `[CONTRIBUTING.md](CONTRIBUTING.md)`.

