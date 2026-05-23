# Agent instructions (Claude Code and compatible tools)

This repo is a native SwiftUI app (SwiftData + CloudKit). Before specifying, planning, or implementing:

## Build and test

This section is the canonical procedure for any agent tool (Cursor, Claude Code, Codex, OpenSpec, etc.). The Cursor rule `.cursor/rules/ios-build-test.mdc` and `openspec/config.yaml` reference this section; do not duplicate the procedure elsewhere.

### Four-step order after substantive Swift / Xcode changes

Run in this exact order from the repo root. Fix failures before advancing to the next step.

1. **`make format`** — auto-fix formatting with `swiftformat .`. No review needed; just re-stage the changes.
2. **`make lint-fix`** — auto-fix correctable lint issues with `swiftlint --fix`, then run `swiftlint lint --strict` as the gate. Resolve any remaining strict violations manually.
3. **`make build`** — bare `xcodebuild build` with no test runner. Catches compile errors in seconds using the same simulator destination and derived-data cache as step 4.
4. **`make test`** — full Swift Testing suite on one iPhone simulator. Only run once steps 1–3 pass cleanly.

Steps 1–3 are seconds-cheap and let you fix lint/compile errors before paying the simulator boot + full-suite cost.

### Per-repo simulator sandbox

Each clone of this repo gets its own dedicated simulator, identified by a unique device name derived from the repo's absolute path (e.g. `iPhone 17 [a1b2c3d4]`). The device lives in the default CoreSimulator device set (required by `xcodebuild`), but the unique name and UDID ensure no two clones ever share a simulator.

The sandbox is set up automatically by `scripts/_sim_sandbox.sh` (sourced by `scripts/_destination.sh`), which is in turn sourced by `scripts/build.sh` and `scripts/test.sh`. You do not need to manage the simulator manually.

**What happens on first run:**

1. `_sim_sandbox.sh` computes a unique device name from the repo path.
2. It resolves the device type and runtime for `SIMULATOR_NAME` via `scripts/resolve_sim_spec.py`.
3. It creates a new simulator in the default set with the unique name and boots it (~30–90 s one-time cost).
4. The UDID is stored in `.build/sim/device.udid` for use by `make sim-*` targets.
5. Subsequent runs find the booted simulator by UDID and reuse it (fast).

**Destination priority:**

1. **`SIMULATOR_UDID`** env var — pins a specific device and skips sandbox management entirely (escape hatch).
2. Any **already-booted** device whose name matches this repo's unique device name.
3. Any **existing but shutdown** device with that name — boots it.
4. **Creates a new device** with the unique name and boots it (first run only).

**Override the device name:**

```bash
SIMULATOR_NAME='iPhone 17' make build
SIMULATOR_NAME='iPad Pro 13-inch (M4)' make test
```

**Simulator management targets** (affect only this repo's device):

```bash
make initialize-sims  # create and boot this repo's simulator without building
make sim-status       # show this repo's simulator status
make sim-shutdown     # shut down this repo's simulator
make sim-clean        # shut down + delete this repo's simulator + remove .build/sim/
```

**Derived data and result bundles** are scoped per repo:

- `-derivedDataPath .build/sim/DerivedData` — build cache stays per-clone.
- `-resultBundlePath .build/sim/results/<timestamp>.xcresult` — test results per run.

**Parallel testing is disabled** for scripted runs (`-parallel-testing-enabled NO`). The scheme has `parallelizable = "YES"` so Xcode's IDE runs can still use per-class clones, but `scripts/test.sh` runs serially on the single warm base sim. Reasons:

1. Each clone re-boots from the base sim (~30–90 s overhead per clone).
2. With multiple agents across repo clones, dozens of clones spawn at once and CoreSimulator races during teardown — manifesting as `Test crashed with signal kill` after tests finish.
3. Serial execution is faster *and* deterministic.

**The UI test bundle is skipped** in scripted runs (`-skip-testing:simple-recurring-budgetsUITests`). XCUITest requires the simulator to have hosted at least one real app lifecycle before its IPC socket is reliable. A freshly-created per-repo sim hasn't had this, so the UI runner times out "while preparing to run tests". The UI bundle only contains `testExample` (trivial launch) and `testLaunchPerformance` (performance baseline), not business-logic tests. Run them in Xcode when needed.

`make sim-clean` runs `scripts/sim_clean.py`, which finds every device whose name contains this repo's unique slug (the base sim plus any orphaned `Clone N of …` left behind by a parallel-testing crash) and deletes them all. It cannot touch other repos' devices.

### What NOT to do (multi-agent safety)

> These commands affect **all** simulators on the machine, including those owned by other repo clones and by Xcode. They will break parallel agent sessions.

- ❌ `pkill Simulator`
- ❌ `killall Simulator`
- ❌ `xcrun simctl shutdown all`
- ❌ `xcrun simctl erase all`
- ❌ Opening Simulator.app on a device an agent is actively using

Use `make sim-shutdown` or `make sim-clean` instead — they operate on this repo's specific UDID only.

Also: all clones must share the same `xcode-select` path. Switching Xcode versions while agents are running restarts CoreSimulatorService and kills booted sims.

### Latest iOS / iPadOS only

- Keep **`IPHONEOS_DEPLOYMENT_TARGET`** aligned with the product rule: latest major OS only; do **not** lower it without an explicit product decision (see `docs/main-prd.md` and `docs/tech-design-doc.md`).
- The app target is universal (iPhone + iPad). One iPhone simulator run compiles the same target; extra iPad simulators are unnecessary unless validating iPad-specific UI.
- Do **not** run tests on multiple simulators or multiple iOS versions unless the user explicitly asks.

### Scheme

The shared scheme is [`simple-recurring-budgets.xcscheme`](simple-recurring-budgets.xcodeproj/xcshareddata/xcschemes/simple-recurring-budgets.xcscheme). Use `-scheme simple-recurring-budgets` (as in `scripts/build.sh` and `scripts/test.sh`).

## Concurrency (Swift 6, default MainActor isolation)

This project uses Swift 6.0 with `SWIFT_APPROACHABLE_CONCURRENCY = YES` and `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (SE-0466). Top-level code is implicitly `@MainActor` — do **not** sprinkle `@MainActor` reflexively. The full rule (with codebase-specific examples) lives at [`.cursor/rules/swift-concurrency.mdc`](.cursor/rules/swift-concurrency.mdc); read it before non-trivial Swift edits. Non-Cursor agents (Claude Code, Codex, OpenSpec) should treat that file as canonical for this section.

Quick rules:

- Off-main work: prefer (1) `nonisolated` sync helpers, (2) `@concurrent` async on a `nonisolated` type, (3) a custom `actor`, (4) `Task.detached` only as a last resort with a justifying comment.
- `Task { ... }` inside MainActor-isolated code stays on main — that is intentional. Do not add `@MainActor in`.
- `ModelContext` is **not `Sendable`**. Pass it at the call site on the MainActor; for background SwiftData work use a `@ModelActor` and pass `PersistentIdentifier`s.
- New value types should be `Sendable` by construction. For cross-isolation seams, mark the protocol `Sendable` (see `AnalyticsClient`).
- `@unchecked Sendable`, `nonisolated(unsafe)`, and `@preconcurrency` require an inline `// concurrency:` justification.
- After any Swift edit, the four-step build/test procedure above is the gate. `make build` must pass clean; never silence a data-race or isolation error with an unsafe escape hatch.

For deeper concurrency design (actor architectures, TaskGroup, AsyncSequence, reentrancy, migration), agents that have access to it should also load the `swift-concurrency` skill.

## High-level docs

Skim and respect:

- `docs/main-prd.md` — product constraints and glossary (including Over/Under vs remaining for the current Budget Period).
- `docs/ux-design-brief.md` — high-level UX guidelines; consult for any UI-touching work.
- `docs/product-features-planning.md` — feature IDs (F-x.xx) and acceptance criteria.
- `docs/tech-design-doc.md` — architecture, persistence/sync, data model, i18n/a11y/testing expectations.

## Swift / iOS conventions

The full rules live in [`.cursor/rules/swift-ios.mdc`](.cursor/rules/swift-ios.mdc); non-Cursor agents (Claude Code, Codex, OpenSpec) should treat that file as canonical for this section. Quick rules:

### Money and currency

- Represent monetary amounts with **`Decimal`** (or storage patterns backed by `Decimal`), not `Double`.
- **Currency is per Budget**, not a single global default. Format amounts using the budget's currency and the user's locale (F-3.04).

### UI and system integration

- Follow **Human Interface Guidelines**: system typography, spacing, and materials.
- New views must support **Dynamic Type** and **Dark Mode** without extra toggles.

### Screen architecture

- **Default pattern:** screens are SwiftUI Views using `@Query` for reads, `@Environment(\.modelContext)` for writes, and domain services in `Domain/` (`BudgetLifecycleService`, `BudgetCalculator`, `PeriodCalculator`) for logic. **No ViewModel by default.**
- **Escalate to an `@Observable` ViewModel only if** the screen has non-trivial draft/form state, owns `async` / `Task` work, chains a multi-step user action, or has expensive derived display state.
- **VM rules when escalated:** `@Observable final class <Screen>ViewModel` owned by the view via `@State`. VM holds draft state + pure logic only. It does **not** store `ModelContext`, does **not** hold `@Query` results, and does **not** fetch. Methods that write take `(context: ModelContext, ...)` at the call site.
- **Grey-area ping:** if a screen is on the fence, ask the user before scaffolding a VM. Mandatory ping triggers: >3 mutable form fields, a framework call (Vision, Speech, PhotosUI, SiriKit/App Intents, network), one input that mutates >1 model property or couples fields, or a screen expected to grow materially in the next 1–2 features.
- Authoritative version: [`docs/tech-design-doc.md`](docs/tech-design-doc.md) §2.1.

### Testing

- Prefer **Swift Testing** for new tests. Place tests in the Xcode test target alongside or mirroring app modules.

### Data, sync, and Xcode project

- When changing models, sync, or app structure, align with [`docs/tech-design-doc.md`](docs/tech-design-doc.md).
- When changing the schema, consider SwiftData models and CloudKit sync early: relationships, uniqueness, and migration impact (F-1.02).
- When editing the Xcode project or schemes, keep target membership and test targets correct.

## Cross-cutting concerns

Some concerns are **ongoing**, not feature-shaped. Every substantive code change that adds or modifies user-facing UI MUST address each of these in the same change (or add an explicit follow-up task before the change is treated complete). Failing to do so is a defect, not a follow-up. The canonical rule lives in [`docs/main-prd.md` §6.8](docs/main-prd.md#68-cross-cutting-ongoing-concerns); per-feature tracking lives in `docs/product-features-planning.md` (F-3.01, F-3.02, F-3.03, F-3.05, F-8.02).

Quick checklist for every UI-touching change:

- **Accessibility** — semantic text styles (`@ScaledMetric` for custom metrics, no fixed frame heights that clip), composed `.accessibilityLabel`/`.accessibilityHint` on composite views and destructive controls, `.accessibilityAddTraits(.isHeader)` on section headings, `swipeActions` paired with `.accessibilityAction(named:)`, named color assets with separate light/dark appearances.
- **Localized source strings** — every new user-facing string keyed in `Localizable.xcstrings` with a translator `comment:`. Never hard-coded English in production views. Locale-invariant strings (app versions, raw ISO codes, monospaced identifiers) use `Text(verbatim:)`. Shared copy across surfaces uses `common.*` keys. Full rules in `docs/tech-design-doc.md` §5.1.
- **Translations** — translations for all 38 storefront locales are shipped and must stay current. After adding or changing string keys, run the **`translate-new-strings` skill** (`.claude/skills/translate-new-strings/SKILL.md`), which drives `scripts/translate_catalog/` in subset mode: `extract.py --missing` → `dispatch_prompts.py` → parallel per-locale subagents → `validate.py --subset` → `merge.py`. The terminal check is `python3 scripts/check_translations.py` — same script `lefthook.yml` runs on `pre-push`, so a clean exit here guarantees the push passes the translation gate. Never omit keying or skip the pipeline step.
- **Mixpanel events** — new user-initiated actions that materially change app state (new destructive action, new CTA, new toggle affecting usage or retention) must fire the corresponding `AnalyticsClient.track(...)` event per [`docs/analytics-spec.md`](docs/analytics-spec.md). No PII; respect consent. Boundary with OSLog: `docs/analytics-spec.md` §17.

## Conflicts and planning

- If the planned direction contradicts those files, say so with a short **Conflict with docs** block (file, summary, resolution: update doc / change plan / intentional exception).
- In **planning-only** modes (no implementation yet), still perform doc checks; written plans should include **Doc alignment** or **Conflicts with docs** when the topic touches product, features, architecture, data model, or sync—and list which `docs/*.md` files will need updates afterward, or none.

## Doc maintenance

When work materially changes product rules, F-x.xx entries, architecture, schema, or global constraints, update the matching `docs/*.md` file(s) or add an explicit task to do so before treating the work complete.

## OpenSpec

OpenSpec CLI merges workflow context from `openspec/config.yaml` (doc checks, apply/verify/archive expectations). Do not rely on editing autogenerated opsx command templates; change behavior via `openspec/config.yaml` and this file.

## Commit and PR style

### Branch names

Format: `u/jimmyho/<tool>/<short-description>`

- **`u/jimmyho/`** — always the prefix.
- **Tool segment** — documents what tool authored the work. Use `+` to combine tools (e.g. `cursor+claude`). Common values: `claude-code` (Claude Code CLI), `claude`, `cursor`, `cursor+claude`, `xcode+claude+cursor`. Omit the tool segment for personal/manual branches.
- **Description** — kebab-case, all lowercase, short feature or fix name (e.g. `fix-delete-budget-nav-stack`, `rewrite-budget-calculator`). No underscores.
- For branches created by Claude Code: `u/jimmyho/claude-code/<short-description>`.

### Commit subject line

Format: `<Past-tense verb> <short description>. (#N)`

- **Past-tense verb** — `Updated`, `Fixed`, `Added`, `Created`, `Implemented`, `Removed`, `Refactored`, `Rewrote`. Match the weight of the verb to the change (don't say "Updated" for a complete feature build; say "Implemented").
- **Sentence case.** No conventional-commit prefix (`feat:`, `fix:`, `chore:`).
- Ends with a **period**, then the PR number `(#N)` at the very end.
- **≤72 characters.** GitHub and `git log --oneline` truncate beyond this. If the subject wants to be longer, move the extra detail into the body.

### Commit body

Optional for tiny one-liner changes; required when a PR contains more than one meaningful area of work.

```
* High-level area of change (feature name, architectural move, etc.)
* Another area of change

Why: one sentence — the product goal or problem this solves.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
```

- Bullets describe **areas of change**, not files or acceptance criteria. Name a feature (and whether it's partial or complete), name a structural refactor — but don't list every task or spec detail. The diff covers that.
- The **`Why:` line** is the one thing the diff can't show. Always include it for feature work and architectural changes.
- Always include the **`Co-Authored-By:` footer** on Claude-generated commits.

### Merging

Always use **Squash and merge**. One PR = one commit on `main`, with the PR number appended by GitHub.

### PR description

```markdown
## What
* Feature or area of change (complete / partial — what's still pending)
* Architectural change, at the structural level
* Infra/config/docs updates grouped into one bullet

## Why
One sentence: the user problem or product goal this PR advances.

## Test plan
- [ ] Golden path: <how to verify the main flow works>
- [ ] Edge case: <anything non-obvious worth checking>
```

- **What bullets are high-level.** One bullet per meaningful area, not per file, spec task, or acceptance criterion. If a feature is partially done, say so.
- **Why** gives reviewers (and future-you) the motivation in plain language.
- **Test plan** is a lightweight sanity-check list, not a QA spec. Two or three bullets is enough.
