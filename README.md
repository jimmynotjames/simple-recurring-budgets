<!--
  README authoring notes (delete before going public, or keep — your call):
  • Blocks marked  > ✍️ **WRITE THIS** …  are prose outlines for you to replace with your own words.
  • Tables and bullet lists outside those blocks are pre-filled from a repo audit — verify, then keep.
  • GitHub "Topics" are set in repo Settings, not in this file. Suggested topic list is at the very bottom.
-->

# Wren — Daily Expense Tracker

> A native iOS / iPadOS app for staying on top of small, recurring everyday spending — built with SwiftUI, SwiftData, and CloudKit sync.

<!-- Badge template — swap the placeholders once the repo is public / shipping. -->
![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20iPadOS-blue)
![Swift](https://img.shields.io/badge/Swift-6.0-orange)
![Min iOS](https://img.shields.io/badge/iOS-26.5%2B-lightgrey)
![License](https://img.shields.io/badge/license-Apache%202.0-green)
[![CI](https://img.shields.io/badge/CI-GitHub%20Actions-2088FF)](.github/workflows/ci.yml)
![Built with AI](https://img.shields.io/badge/code-~100%25%20AI--written-blueviolet)
<!-- Optional once live: App Store badge, TestFlight badge, build-status badge wired to Actions. -->

---

> ✍️ **WRITE THIS — Elevator pitch (2–4 sentences).** This is the first thing an employer or engineer reads.
> - What Wren is in one line, and who it's for (the "$30/day on coffee, $100/week on clothes" persona).
> - The wedge: in-the-moment "can I afford this *right now*?" — not a full personal-finance suite, not bank integration.
> - Why it exists (most budgeting apps are heavyweight; logging an expense should take seconds).
> - One sentence on what makes the *codebase* interesting (e.g. "built almost entirely through agentic AI development with a spec-driven workflow").

## 🤖 An experiment in agentic AI development

> ✍️ **WRITE THIS — your headline story, above the fold (1–2 tight paragraphs).** This is the lead. Hints for what to hit:
> - **The thesis in one breath.** Essentially every line of this app was written by AI agents (all but two) — a deliberate experiment in *agentic* development, where the human sets direction and the agents write the code.
> - **What that actually looked like for you.** Most of the effort went into the *prompt, the plan, and the product/UX specs* — plus reviewing PRs and conversing with the agent — not typing implementation. AI also drove the visual design, app icon, and color palette.
> - **Why it didn't turn into chaos.** A hand-written PRD + UX brief for governance, OpenSpec to impose discipline on agents, CI gates they can't bypass, and a habit of running regular audits. (Keep this to a sentence here — the long version lives in the retrospective.)
> - **Land it.** One line on what you took away from it / why it's worth a reader's time.
>
> 📖 **The full story — build order, what worked, the tooling tug-of-war between Cursor / Claude Code / Xcode, and where AI struggled — is in [`RETROSPECTIVE.md`](RETROSPECTIVE.md).** For the engineering map, see [`ARCHITECTURE.md`](ARCHITECTURE.md).

## Screenshots

> ✍️ **ADD THIS.** 3–5 screenshots (or a short GIF) of the core screens: Budgets list, Budget detail with the carry-over chip, Add Expense, Settings. A single hero shot up top + a row of thumbnails reads well. The App Store screenshots under `fastlane/` are a good source.

---

## Table of contents

- [An experiment in agentic AI development](#-an-experiment-in-agentic-ai-development)
- [About](#about)
- [Status](#status)
- [Features](#features)
- [Tech stack](#tech-stack)
- [Architecture](#architecture)
- [Project structure](#project-structure)
- [Dependencies](#dependencies)
- [Localization &amp; accessibility](#localization--accessibility)
- [Testing](#testing)
- [Tooling, CI &amp; release](#tooling-ci--release)
- [Built with agentic AI](#built-with-agentic-ai)
- [What this project demonstrates](#what-this-project-demonstrates)
- [Getting started](#getting-started)
- [Documentation](#documentation)
- [License, trademarks &amp; contributing](#license-trademarks--contributing)

---

## About

> ✍️ **WRITE THIS — The problem & the approach.** A few short paragraphs. Suggested beats:
> - **The problem.** Recurring everyday spend (food, coffee, groceries) is hard to discipline; bank-linked apps lag ~2 days and miss tips; existing apps assume *their* mental model of your finances.
> - **The approach.** Per-category daily/weekly/biweekly/monthly allowances; a live "remaining this period" number plus a separate signed **carry-over** so you always know if you're ahead or behind.
> - **The constraints that shaped it.** No backend (CloudKit only), Apple-first dependency policy, `Decimal` money everywhere, per-budget currency, privacy-first analytics.
> - **What you'd want to talk about in an interview** (pull from [Architecture](#architecture) below): the carry-over "live walker" algorithm, SwiftData + CloudKit single-store split-brain prevention, the 49-locale AI translation pipeline.

## Status

- **Pre-release / greenfield** — heading to TestFlight and the Apple App Store. Has **not** shipped to production yet.
- Schema is `SchemaV1`, evolved in place (no migration stages yet) — see `docs/tech-design-doc.md` §3.3.
- Versioned product/technical docs and an OpenSpec change history are tracked in-repo.

---

## Features

> ✍️ **WRITE / TRIM THIS.** Keep it benefit-led and short; the full acceptance criteria live in [`docs/product-features-planning.md`](docs/product-features-planning.md). Starter list (verify against current build):

- 💸 **Fast expense logging** — add an expense in as few taps as possible; recents-assisted entry.
- 📊 **Recurring budgets** — daily, weekly, biweekly, monthly, or a fixed-window "Specific Dates" trip budget.
- 🔁 **Carry-over** — a per-budget signed surplus/deficit that tells you if you're ahead or behind over time (toggleable).
- ➕ **Add funds** — top up a period's allocation; overspend and add-funds excess settle into carry-over live.
- ⏸️ **Pause / resume** budgets, plus distinct **Reset Carry-Over / Reset Budget / Delete Budget** actions.
- 💱 **Per-budget currency** (ISO 4217) with locale-aware formatting; no FX conversion.
- ☁️ **CloudKit sync** across the user's devices; settings sync via iCloud key-value store.
- 🌗 **Dark Mode**, **Dynamic Type**, and **VoiceOver** support throughout.
- 🌍 **49 App Store storefront locales**.
- 🔒 **Privacy-first analytics** — consent-gated, no PII, off by default in strict-opt-in jurisdictions.

---

## Tech stack

| Layer | Choice |
|---|---|
| **Language** | Swift 6.0 — strict concurrency, default `@MainActor` isolation |
| **UI** | SwiftUI (`NavigationStack` value-based routing, `@Observable` state) |
| **Persistence** | SwiftData (`@Model`, `@Query`, in-memory containers for tests) |
| **Sync** | CloudKit (`cloudKitDatabase: .automatic`) + `NSUbiquitousKeyValueStore` for preferences |
| **Money** | `Decimal` end-to-end (never floating point); per-budget currency |
| **Min OS** | iOS / iPadOS **26.5** (latest-major-only policy) |
| **Targets** | iPhone + iPad (`TARGETED_DEVICE_FAMILY = 1,2`); macOS is a longer-term goal |
| **Analytics** | Mixpanel (lazy-init, consent-gated) + Apple unified logging (`OSLog`) for diagnostics |
| **Unit tests** | Swift Testing (`@Test` / `#expect`) |
| **UI tests** | XCTest / XCUITest + `performAccessibilityAudit()` |
| **i18n** | Xcode String Catalogs (`.xcstrings`) + a custom AI translation pipeline |
| **Local gates** | Lefthook · SwiftLint · SwiftFormat · gitleaks |
| **CI/CD** | GitHub Actions + Fastlane (App Store Connect API) |
| **Release automation** | Fastlane lanes for TestFlight, App Store, metadata, screenshots |
| **Spec workflow** | OpenSpec (spec-driven change tracking) |
| **AI dev workflow** | Claude Code / Cursor agents, `AGENTS.md`, custom repo skills |

**At a glance:** ~102 app Swift files · 4 SwiftData entities · ~82 unit-test files · 16 UI-test files (30 accessibility-audit + 15 user-journey tests) · 49 Python pipeline scripts · 49 localized storefronts · 1 direct third-party runtime dependency.

---

## Architecture

> ✍️ **WRITE THIS — narrate the 2–3 decisions you're proudest of.** The facts below are accurate; add the *why* in your own voice. Candidates worth a paragraph each:
> - **Designed for longevity & minimal maintenance (lead with this — it ties the whole tech philosophy together).** The explicit goal: *I may not touch this app for years, and I don't want future-me fighting it.* So — target the **latest iOS only** (minimal backward-compat surface), lean on **stable, documented Apple APIs** (no undocumented/private behavior that breaks on OS updates), and keep **external dependencies near-zero** (one direct package). Fewer moving parts = fewer things that rot.
> - **View + Services, ViewModels on demand.** Pure domain services in `Domain/` hold the testable math; thin screens read via `@Query` and only escalate to an `@Observable` ViewModel for real draft/form state. (tech-design-doc §2.1)
> - **The carry-over "live walker."** Carry-over is never stored — `BudgetCalculator.snapshot(...)` recomputes it from history at read time, with an *asymmetric live coupling* rule (overspend lands immediately; provisional slack waits for the period to close). (PRD §6.7, tech-design-doc §3.2 / §5.4)
> - **Single-store split-brain prevention.** CloudKit-enabled and local-only `ModelConfiguration`s are pinned to the same on-disk URL so an offline-first launch isn't stranded in a forked store. (tech-design-doc §4.1)

**The non-negotiables (pulled from the docs):**

- **No app-owned backend.** All data is on-device (SwiftData) and syncs through the user's own iCloud (CloudKit). Apple-first dependency policy.
- **Value-based navigation.** Routes carry a model's stable `UUID`, never a live object — serializable for future deep links / widgets / App Intents.
- **Domain layer is SwiftUI-free.** `PeriodCalculator`, `BudgetCalculator`, and `BudgetLifecycleService` are pure and unit-tested in isolation.
- **Container creation never `fatalError`s.** Failures surface a Retry / Send-Feedback screen instead of crashing.

**Start with [`ARCHITECTURE.md`](ARCHITECTURE.md)** for the high-level, human-readable map; [`docs/tech-design-doc.md`](docs/tech-design-doc.md) is the exhaustive reference behind it.

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

| Package | Version | Why | Notes |
|---|---|---|---|
| [`mixpanel-swift`](https://github.com/mixpanel/mixpanel-swift) | 6.3.0 | Product analytics | Direct; lazy-init, consent-gated, no PII |
| [`mixpanel-swift-common`](https://github.com/mixpanel/mixpanel-swift-common) | 1.0.1 | — | Transitive (via Mixpanel) |
| [`json-logic-swift`](https://github.com/advantagefse/json-logic-swift) | 1.2.4 | — | Transitive (via Mixpanel) |

Everything else is **Apple frameworks**: SwiftUI, SwiftData, CloudKit, Foundation, `OSLog`, StoreKit (rating prompt), and the String Catalog toolchain. SPM bumps are manual (no `Package.swift`; Dependabot tracks GitHub Actions only).

---

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
- **CI (GitHub Actions, [`ci.yml`](.github/workflows/ci.yml)):** `lint`, `secrets` (gitleaks full-history), `i18n-gates` (translation/source/metadata checks), `build`, and `unit-tests` — version-pinned to match local installs. Full UI suite runs on-demand via `/test-full`.
- **Release (Fastlane):** lanes for `beta` (TestFlight), `release` (App Store), `push_metadata`, and `screenshots`, all guarded by a pre-build secrets check (`scripts/verify_release_secrets.sh`). App Store Connect API key auth; secrets live outside the repo.
- **Spec-driven workflow:** [OpenSpec](https://github.com/Fission-AI/OpenSpec) change proposals under `openspec/`.

---

## Built with agentic AI

> **Premise:** essentially **100% of this codebase was written by AI agents — every line but two** — as a deliberate showcase of agentic-AI software development. The role here was engineer-as-director: setting requirements, reviewing, and gating, while agents produced the code.

> ✍️ **WRITE THIS — this is the headline differentiator; give it room.** Beats to consider:
> - **The experiment.** State it plainly: a real, App-Store-bound iOS app where AI wrote all the code save two lines — not a toy or a demo. Mention the timeframe / scale if you want it to land.
> - **What "agentic AI development" means to you (define the term — don't assume the reader shares your definition).** AI *generates* the code; your time goes into the **prompt, the plan, and the product specs**, plus conversing/iterating with the agent. You **still manually reviewed PRs** (sometimes a skim, but a human gate) — engineer-as-director, not hands-off autopilot.
> - **Where the hard human work actually went.** The initial drafts of [`docs/main-prd.md`](docs/main-prd.md) and [`docs/ux-design-brief.md`](docs/ux-design-brief.md) were **written by hand** — they're the high-level governance that keeps every agent, feature, and decision aligned. This is the leverage point: invest in the spec, and the agents stay on-rails.
> - **AI beyond code.** You also used AI for **UI/visual design, the app icon, and the color palette** (the warm earth-tone theme). Worth calling out as evidence of an end-to-end AI-driven product, not just codegen.
> - **How you kept it rigorous (the real skill on display).** [`AGENTS.md`](AGENTS.md) as canonical agent instructions, a spec-driven **OpenSpec** workflow, enforced cross-cutting-concern checklists (a11y, localization, analytics, UI-test screen objects), and CI gates agents can't bypass — so quality didn't depend on any single generation being right.
> - **Custom agent tooling you built.** Repo-local skills and parallel multi-agent pipelines — e.g. fanning out one model subagent *per locale* to translate/transcreate 49 storefronts, and to generate culturally-tuned screenshot seed data.
> - **Agents reach into ops too (TODO — not done yet, write once shipped).** The Mixpanel analytics dashboards are also generated by agents conversing with the **Mixpanel MCP server**, using [`docs/analytics-spec.md`](docs/analytics-spec.md) as the source of truth — so the spec drives both the in-app event code *and* the dashboards that read them.
> - **The honest version.** What worked, what you had to guard against (drift audits in [`docs/audits/`](docs/audits)), and how you stayed the engineer-in-the-loop — the two hand-written lines are a nice concrete hook for *why* they were the exception.

## What this project demonstrates

> ✍️ **WRITE THIS — the "for employers" section.** A tight bulleted list of skills this repo is evidence of. Pull specifics from the docs so each bullet is concrete. Suggested skeleton:
> - **Modern Apple platform engineering** — Swift 6 strict concurrency, SwiftUI, SwiftData + CloudKit, no third-party UI frameworks.
> - **Non-trivial domain modeling** — the carry-over algorithm (asymmetric live coupling, paused-period handling, reset semantics) specified in the PRD and implemented as pure, tested services.
> - **Production-readiness discipline** — privacy-first analytics, crash-free container recovery, secrets hygiene, branch-protected CI, App Store release automation.
> - **Engineering for longevity** — deliberate low-maintenance bets (latest-OS-only, documented Apple APIs only, near-zero dependencies) so the app survives years of neglect without rotting.
> - **Internationalization & accessibility at scale** — 49 locales and a VoiceOver/Dynamic-Type-per-change rule, both gated in CI.
> - **Process & documentation** — versioned PRD / tech-design / UX docs, OpenSpec change history, and a reproducible agentic-development workflow.
> - **(Optional) Product thinking** — a clear wedge, defined personas, and deliberate non-goals.

---

## Getting started

You can build and run on the iOS Simulator with **no secrets and no Apple Developer account**:

```bash
make system    # one-time: installs Lefthook, SwiftLint, SwiftFormat, gitleaks; checks Xcode + Python
make build     # Debug → Simulator build using committed placeholder config
make test      # boots the repo's simulator and runs the full suite
```

Full setup — including the two-tier flow (Simulator-only vs. shipping/forking for distribution), secrets configuration, and Fastlane — is in **[`CONTRIBUTING.md`](CONTRIBUTING.md)**.

## Documentation

| Document | Description |
|---|---|
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | High-level, human-readable engineering map |
| [`RETROSPECTIVE.md`](RETROSPECTIVE.md) | Essay on building this app with agentic AI |
| [`docs/main-prd.md`](docs/main-prd.md) | Product requirements and global constraints |
| [`docs/ux-design-brief.md`](docs/ux-design-brief.md) | UX guidelines |
| [`docs/product-features-planning.md`](docs/product-features-planning.md) | Feature IDs and acceptance criteria |
| [`docs/tech-design-doc.md`](docs/tech-design-doc.md) | Technical architecture, persistence/sync, tooling |
| [`docs/analytics-spec.md`](docs/analytics-spec.md) | Analytics events, consent, and no-PII rules |
| [`docs/audits/`](docs/audits) | Periodic architecture / code / localization drift audits |
| [`AGENTS.md`](AGENTS.md) | Canonical instructions for AI coding agents in this repo |

---

## License, trademarks & contributing

- **License.** Source code is licensed under the **Apache License 2.0** — see [`LICENSE`](LICENSE).
- **Trademarks.** The **Wren** name and app icon are trademarks of Jimmy Ho and are **not** covered by the code license. Forks that distribute an app must replace the name, icon, and App Store marketing assets before shipping — see [`TRADEMARK.md`](TRADEMARK.md).
- **Contributing.** See [`CONTRIBUTING.md`](CONTRIBUTING.md).

<!--
  GitHub Topics (set these in repo Settings → About → Topics; they don't render in the README):
  swift · swift6 · ios · ios-app · ios-development · ipados · swiftui · swiftdata · cloudkit
  swift-testing · xcuitest · fastlane-ios · localized · internationalization · accessibility
  expense-tracker · budgeting · personal-finance · mixpanel · openspec
  agentic-ai · agentic-ai-development
-->
