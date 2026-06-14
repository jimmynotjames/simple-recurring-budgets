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

`make test-ui` — runs only the UI test pass (`AccessibilityAuditTests` + `UserJourneyTests`). Use when iterating on UI test failures after `make test-unit` is green. Does not re-run unit tests. The simulator must have hosted at least one prior app lifecycle (i.e. run `make test-unit` or `make initialize-sims && make build` first in a fresh session).

`make coverage` — line-coverage report from the latest unit `.xcresult` (so run `make test-unit` or `make test` first). Report-only: nothing gates on the numbers; it exists for audits and "what's untested?" questions. Coverage is collected on the unit pass only (`-enableCodeCoverage YES`); the UI pass is uninstrumented.

**Running a subset of tests (ad-hoc):** use `make test-only ONLY="<id> [more...] [--ui]"` or `bash scripts/test-only.sh <id> ...` — each identifier becomes an `-only-testing:<id>` filter (`Target/Suite` or `Target/Suite/method()`). Example: `make test-only ONLY="simple-recurring-budgetsTests/RatingPromptCoordinatorTests"`. This routes through the sandboxed sim + DerivedData and is a single allowlisted command. **Do not** hand-build `source scripts/_destination.sh && xcodebuild test -only-testing:...` — the `source` segment triggers a permission prompt and bypasses the sandbox; `test-only.sh` exists precisely to avoid that.

Steps 1–3 are seconds-cheap and let you fix lint/compile errors before paying the simulator boot + full-suite cost.

**One-command gate:** `make gate` (or `bash scripts/gate.sh`) runs all four steps in order, tees to `tmp/gate.log`, stops at the first failure, and exits with that step's code. Prefer it over hand-writing the chain — it's a single allowlisted command, so it never prompts (unlike the `(make … ) > tmp/gate.log 2>&1; echo "EXIT=$?"` subshell form, which splits into un-allowlistable segments). Run it `run_in_background=true` to be re-invoked on completion instead of blocking. Use the individual `make` targets when you only need one step or want to iterate on a single failure.

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

**Simulator concurrency knob — `SRB_SIM_MAX`** (default `2`, range `1–3`, set by `scripts/_sim_concurrency.sh`). Controls how many simulators the **UI pass** may use at once. Every test run prints a resource-use reminder. Scale down on tight RAM or when multiple repos run at once; the unit pass is always serial and ignores this knob.

| `SRB_SIM_MAX` | UI pass | When to use |
| --- | --- | --- |
| `1` | `-parallel-testing-enabled NO` (serial, 1 sim) | Lightest. Downshift here if the UI pass flakes, or when several repos run at once. |
| `2` (default) | `-parallel-testing-enabled YES -maximum-concurrent-test-simulator-destinations 2` | Balanced default (≈16 GB Apple silicon, ≤ 2 repos at once). |
| `3` | …`-destinations 3` | Only with headroom — RAM-heavy. |

```bash
SRB_SIM_MAX=1 make test     # downshift: serial, lightest
SRB_SIM_MAX=3 make test-ui  # upshift: only if the machine is clear
```

> **24-hour time:** Sandbox simulators force 24h time globally. UI tests that assert AM/PM strings must add `-AppleICUForce24HourTime NO -AppleICUForce12HourTimeFormat YES` to `app.launchArguments` to get 12-hour output.

See `docs/simulator-setup.md` for RAM guidance, flake-retry behavior, and clone-risk history.

**The UI test bundle is skipped in pass 1** (`-skip-testing:simple-recurring-budgetsUITests`). XCUITest requires the simulator to have hosted at least one real app lifecycle before its IPC socket is reliable. A freshly-created per-repo sim hasn't had this, so the UI runner times out "while preparing to run tests". Pass 2 of `scripts/test.sh` then runs `AccessibilityAuditTests` (accessibility regression tests, XCTestCase), `UserJourneyTests` (core flow tests, XCTestCase), and `ClearAmountButtonUITests` with `-only-testing`. Note: Apple does not support `import Testing` in unhosted XCUITest bundles; these suites use XCTestCase with `continueAfterFailure = false`. `testExample` and `testLaunchPerformance` are intentionally excluded from scripted runs.

`make sim-clean` runs `scripts/sim_clean.py`, which finds every device whose name contains this repo's unique slug (the base sim plus any orphaned `Clone N of …` left behind by a parallel-testing crash) and deletes them all. It cannot touch other repos' devices.

### What NOT to do (multi-agent safety)

> These commands affect **all** simulators on the machine, including those owned by other repo clones and by Xcode. They will break parallel agent sessions.

- ❌ `pkill Simulator` — **hard-blocked** by the PreToolUse hook (`scripts/hooks/guard_bash_hygiene.sh`, rule 5)
- ❌ `killall Simulator` — **hard-blocked**
- ❌ `xcrun simctl shutdown all` / `erase all` / `delete all` — **hard-blocked**
- ❌ `xcrun simctl delete unavailable` — **hard-blocked** (can remove another repo's device whose runtime is temporarily gone)
- ❌ Opening Simulator.app on a device an agent is actively using

The hook denies only the machine-wide `all` / `unavailable` / `pkill` / `killall` forms; scoped commands (`simctl shutdown <udid>`, `simctl delete <udid>`) stay allowed. Use `make sim-shutdown` or `make sim-clean` instead — they operate on this repo's specific UDID / slug only.

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
- **Previews live in `<View>+Previews.swift`, not in the view's own file.** Xcode 16+ XOJIT previews crash (SIGSEGV) when the previewed file spans cross-file `some View` extensions — the JIT can't resolve opaque-type layouts from the prebuilt binary. Splitting the previews out fixes it (PR #239). Fallback: Editor → Canvas → Use Legacy Previews Execution.
- Authoritative version: [`docs/tech-design-doc.md`](docs/tech-design-doc.md) §2.1.

### Testing

- Prefer **Swift Testing** for new tests. Place tests in the Xcode test target alongside or mirroring app modules.

### Data, sync, and Xcode project

- When changing models, sync, or app structure, align with [`docs/tech-design-doc.md`](docs/tech-design-doc.md).
- When changing the schema, consider SwiftData models and CloudKit sync early: relationships, uniqueness, and migration impact (F-1.02).
- When editing the Xcode project or schemes, keep target membership and test targets correct.

## Cross-cutting concerns

Some concerns are **ongoing**, not feature-shaped. Every substantive code change that adds or modifies user-facing UI MUST address each of these in the same change (or add an explicit follow-up task before the change is treated complete). Failing to do so is a defect. See [`docs/main-prd.md` §6.8](docs/main-prd.md#68-cross-cutting-ongoing-concerns).

Quick checklist for every UI-touching change:

- **Accessibility** — semantic text styles (`@ScaledMetric` for custom metrics, no fixed frame heights that clip), composed `.accessibilityLabel`/`.accessibilityHint` on composite views and destructive controls, `.accessibilityAddTraits(.isHeader)` on section headings, `swipeActions` paired with `.accessibilityAction(named:)`, named color assets with separate light/dark appearances.
- **Localized source strings** — every new user-facing string keyed in `Localizable.xcstrings` with a translator `comment:`. Never hard-coded English in production views. Locale-invariant strings (app versions, raw ISO codes, monospaced identifiers) use `Text(verbatim:)`. Shared copy across surfaces uses `common.*` keys. Full rules in `docs/tech-design-doc.md` §5.1.
- **Translations** — 49 storefront locales must stay current. After adding or changing string keys, run the **`translate-new-strings` skill** (`.claude/skills/translate-new-strings/SKILL.md`) **autonomously**. Gate: `python3 scripts/check_translations.py` (same check `pre-push` runs). Never skip keying or the pipeline. Count-dependent strings (e.g. `%lld items`) need `pluralize_keys.py`. Quality audit: **`audit-translations` skill** (`scripts/translate_audit/`). See *Running the translation pipelines* below. **Push gate also blocks on `en` source `state: "new"`** (Xcode-extracted but unconfirmed): re-run `merge.py` to promote them (`new → translated`); or for keys with no translation yet, `add_keys.py --force` then `merge.py`.
- **App Store listing metadata** — the store listing copy (name, subtitle, keywords, description, promotional text, release notes) is a *release-time* concern, not a per-change one. It lives in `fastlane/metadata/` and is transcreated into all 49 storefronts by the separate **`appstore-translate-metadata` skill** (`/appstore:translate-metadata`) / `scripts/translate_metadata/` pipeline (gate: `python3 scripts/translate_metadata/check_metadata.py`). App Store Connect storefront codes (`de-DE`, `no`, `nl-NL`) differ from the in-app runtime codes; `metadata_locales.py` owns the map. Author English copy in `fastlane/metadata/en-US/` first, then run the skill (also autonomous). Like the in-app pipeline, never write ad-hoc Python — use `scripts/translate_metadata/*`. Two audits: `audit.py` (structural — presence + char limits) and `audit_semantic.py` (semantic — voice/transcreation/keyword-ASO/cultural quality, mirroring the in-app audit). The skill wires the semantic audit into an **autonomous refine pass** after merge: Opus auditor per storefront → `audit_semantic.py --write-manifest` → re-transcreate the medium+ findings → re-audit (cap 2 rounds, residual surfaced for owner review).
- **App Store screenshot demo-content** — the per-locale demo budgets/expenses the app is seeded with when capturing localized App Store screenshots are a *release-time* concern, generated by the **`appstore-generate-screenshot-seeding` skill** (`/appstore:generate-screenshot-seeding`) / `scripts/screenshot_content/` pipeline (gate: `python3 scripts/screenshot_content/check_content.py`). It reuses `metadata_locales.py` for the runtime↔storefront map and writes a runtime-keyed catalog under `simple-recurring-budgetsUITests/ScreenshotSeeds/` (UI-test target only — never ships). Capturing + uploading the screenshots is handled by the **`appstore-generate-push-screenshots` skill** (`/appstore:generate-push-screenshots`), which runs `fastlane screenshots` then the self-healing upload controller; see `fastlane/SETUP.md`.
- **Mixpanel events** — new user-initiated actions that materially change app state (new destructive action, new CTA, new toggle affecting usage or retention) must fire the corresponding `AnalyticsClient.track(...)` event per [`docs/analytics-spec.md`](docs/analytics-spec.md). No PII; respect consent. Boundary with OSLog: `docs/analytics-spec.md` §17.
- **UI test screen objects** — when a view's navigation structure, button labels, toolbar items, or sheet routes change, update the matching screen object in `simple-recurring-budgetsUITests/` (`BudgetsScreen.swift`, `BudgetDetailScreen.swift`, `AddBudgetScreen.swift`, `AddExpenseScreen.swift`, `SettingsScreen.swift`) before the change is treated complete. Then run `make test-ui` to confirm no journey regressions. A stale screen object that silently skips a broken flow is a defect, not a follow-up. UI tests run slowly; update screen objects proactively so agents don't loop on test failures after the fact.

### Running the translation pipelines (Claude Code & Cursor)

Three pipelines, each driven by a skill that **any** agent/editor can run; the only tool-specific
part is the parallel fan-out. This subsection is the canonical spec — `.cursor/rules/project.mdc`
and the skills point here.

- **App strings** — `translate-new-strings` skill → `scripts/translate_catalog/` (incl. glossary
  `glossary*.py` and `pluralize_keys.py`). Gate: `check_translations.py`.
- **Translation quality audit** — `audit-translations` skill → `scripts/translate_audit/` (per-locale
  Opus semantic audit + deterministic `consistency_check.py`). Advisory, not a gate.
- **App Store metadata** — `appstore-translate-metadata` skill (`/appstore:translate-metadata`) →
  `scripts/translate_metadata/` (structural `audit.py` + semantic `audit_semantic.py`, the latter
  now driven as an autonomous post-merge remediation loop via `--write-manifest`). Gate:
  `check_metadata.py`.
- **App Store screenshot demo-content** — `appstore-generate-screenshot-seeding` skill
  (`/appstore:generate-screenshot-seeding`) → `scripts/screenshot_content/`. Gate: `check_content.py`.
  Generates the per-locale demo (seeding) data the screenshots are captured from; reuses
  `metadata_locales.py` for the locale map. Capture + upload: `appstore-generate-push-screenshots`
  skill (`/appstore:generate-push-screenshots`), which runs `fastlane screenshots` then
  `upload_with_retry.sh`.

**Stale-output hygiene (all fan-out pipelines).** Each pipeline's `validate.py`/`merge.py`/
`audit_report.py` reads **every** file in its `tmp/<pipeline>-outputs/` dir, not just the
current manifest — so per-locale leftovers from a previous run silently contaminate the next
(re-merged, re-counted as done, or skewing a report). `scripts/pipeline_tmp.py status|clean
<group>` (allowlisted, no prompt) inspects or clears the gitignored `tmp/` working dirs;
groups are `translate`, `translate-audit`, `metadata`, `screenshot-content`, `size-check` (or
`all`). Every pipeline skill runs `clean` as a **pre-flight** and offers it as **end-of-run
cleanup**. (The size-check's `run.sh` already self-wipes its dir; the others rely on this.)

**Per-locale register notes are intentionally duplicated, not DRY.** The in-app
`REGIONAL_NOTES` (`scripts/translate_catalog/dispatch_prompts.py`) and the App Store
`CULTURAL_NOTES` (`scripts/translate_metadata/dispatch_prompts.py`) both carry per-language
register/formality guidance. They overlap **only** in the *formality decision* per language
(de→"du", ja→です/ます, ko→해요체); everything else legitimately differs (UI dialect/length vs
ASO positioning/keyword/marketer voice), and some markets phrase the formality call itself
differently for marketing. Issue #173 proposed single-sourcing them; we **deliberately closed
it without code consolidation** because a shared-prose module needed a per-storefront override
map that re-duplicated the formality sentence anyway. **Do not re-open this as a DRY violation.**
The one real obligation is the **sync rule**: when you change a language's *formality decision*
in one map, change it in the other (wording may differ; the formality call must match).

**Cross-tool execution.** Claude Code fans out parallel per-locale subagents (`.claude/agents/`, model-pinned — Haiku for translation, Opus for audit/glossary). Cursor runs the same fan-out step inline and serially — identical result, no subagent files needed. Run all pipelines **without prompting for approval**; scripts and agents are allowlisted in `.claude/settings.json` and `~/.cursor/cli-config.json`.

### Orchestrator-model preflight (Sonnet-tuned skills)

A few skills are written so the **orchestrator** (the session model running the skill) can be
**Sonnet** — orchestration is mechanical (script calls, parallel fan-outs, deterministic
threshold branches) while the pinned-Opus subagents do the language work. Claude Code exposes
**no session-model env var** (so a hook or script can't detect it), and skill frontmatter can't
pin the session model — so these skills self-check at **Step 0** instead. The check is advisory
(it relies on the model reading its own identity line), not an enforced gate.

1. **Read** your current session model from your environment context (the line "You are powered
   by the model named …").
2. **If it is not Sonnet, stop and confirm before running any step.**
   - **Claude Code:** `AskUserQuestion` — *"This skill is tuned to orchestrate on Sonnet; this
     session is `<model>`. Proceed on `<model>`, or stop and switch first?"* Spell out the
     trade-off in the options: Opus works but is pricier with no quality gain; a model **weaker
     than Sonnet** (e.g. Haiku) may make the loop/threshold judgments unreliable. Options:
     *Proceed on `<model>`* / *Stop — I'll switch to Sonnet*.
   - **Cursor** (no AskUserQuestion): print the same as a short markdown block and wait for a reply.
   - Do **not** run any later step until the user answers.
3. On *proceed*, continue normally. On *stop*, tell them to re-invoke after `/model sonnet`, then
   end. The Opus subagents stay Opus regardless of the session model (pinned in their
   `.claude/agents/*.md` definitions), so switching the session to Sonnet never weakens the
   language work.

Skills that run this preflight: `appstore-generate-screenshot-seeding`,
`appstore-generate-push-screenshots`, `appstore-translate-metadata`.

## Platform compatibility workarounds

When a workaround exists solely because of a known platform bug, framework limitation, or SDK false positive — not because of app logic — tag it with a structured comment so it can be found and reassessed without reading every file.

### Tag format

```
// iOS-COMPAT(VERSION): one-line summary of the bug.
//   Optional additional detail, reproduction conditions, issue number, etc.
//   When fixed upstream: what to remove or revert.
```

Use `iOS-COMPAT(17+)` for bugs first seen on iOS 17, `iOS-COMPAT(26.x)` for bugs specific to iOS 26.x, etc. Use `iOS-COMPAT(?)` when the exact version is unknown.

### Rules

- Add the tag **on the comment immediately before the workaround code**, not in a distant docstring. The tag must be greppable at the callsite.
- Include: what the bug is, which platform version introduced it, and what condition would allow removal.
- Cross-link related workarounds with "Search `iOS-COMPAT`…" so a future agent can find the full set.
- **Do not suppress test failures, hide elements from accessibility, or add layout hacks without this tag** when the root cause is a platform bug rather than app code.

### Auditing

To find every workaround in the repo:

```bash
grep -rn "iOS-COMPAT" . --include="*.swift"
```

A future agent that upgrades the minimum iOS deployment target should run this command, evaluate each tagged site against the new SDK, and remove the workaround + tag if the platform bug is resolved.

### Current inventory (as of iOS 26.x)

| File | Tag | Summary |
|------|-----|---------|
| `Views/Shared/DecimalInputField.swift` | `iOS-COMPAT(17+)` | Two SwiftUI TextField bugs require a UIViewRepresentable wrapper |
| `UITestHelpers.swift` | `iOS-COMPAT(17+)` | XCUITest focus tracking doesn't sync with UIViewRepresentable UITextField; double-tap workaround in `createBudget` and `addExpense` helpers |
| `AddBudgetScreen.swift` | `iOS-COMPAT(17+)` | Same UITextField focus workaround in `fillAllocation()` |
| `AddExpenseScreen.swift` | `iOS-COMPAT(17+)` | Same UITextField focus workaround in `fillAmount()` |
| `AccessibilityAuditTests.swift` | `iOS-COMPAT(26.x)` | `performAccessibilityAudit` false positives: `.elementDetection`, `.sufficientElementDescription`, `.dynamicType`, `.textClipped` |

## Infra and state locality

Prefer self-contained, per-repo solutions over machine-global or shared state. When designing infra (test concurrency, locks, caches, coordination), do **not** introduce folders or state that live outside the repo or are shared across clones; cap resources per-repo with a static knob instead. Multiple clones of a repo are already independent, so cross-repo parallelism is effectively free — favor a small per-repo cap over a shared coordinator. (This is why simulator concurrency is the per-repo `SRB_SIM_MAX` knob in § Build and test rather than a machine-wide semaphore.)

> Mirrored in `.cursor/rules/infra-state-locality.mdc` and the global `~/.claude/CLAUDE.md`; these copies are intentionally redundant so Claude Code and Cursor stay in sync at both repo and user scope.

## Conflicts and planning

- If the planned direction contradicts those files, say so with a short **Conflict with docs** block (file, summary, resolution: update doc / change plan / intentional exception).
- In **planning-only** modes (no implementation yet), still perform doc checks; written plans should include **Doc alignment** or **Conflicts with docs** when the topic touches product, features, architecture, data model, or sync—and list which `docs/*.md` files will need updates afterward, or none.

## Doc maintenance

When work materially changes product rules, F-x.xx entries, architecture, schema, or global constraints, update the matching `docs/*.md` file(s) or add an explicit task to do so before treating the work complete.

## OpenSpec

OpenSpec CLI merges workflow context from `openspec/config.yaml` (doc checks, apply/verify/archive expectations). Do not rely on editing autogenerated opsx command templates or packaged skills under `.claude/skills/openspec-*` or `.cursor/skills/openspec-*` — those files are regenerated when OpenSpec updates and any edits will be lost. **Behavioral overrides for OpenSpec workflows belong in `openspec/config.yaml` (CLI-injected context) and this file (always-on agent rules), not in skill files.**

### Skill behavior overrides (apply to every editor / agent)

These overrides apply whenever the corresponding OpenSpec skill or `/opsx-*` command is invoked, regardless of what the skill file itself says. The agent must follow these instead of the default skill behavior:

- **`openspec-archive-change` / `/opsx:archive`** — when delta specs exist, **sync them automatically** without prompting "do you want to sync?". The standing preference is always yes. Invoke `openspec-sync-specs` inline (via the Skill tool from the parent agent — do not delegate to a sub-agent). Only prompt the user if the sync itself surfaces a genuine merge ambiguity (e.g. a MODIFIED block targets a requirement that doesn't exist in main, or a delta conflicts with a parallel main-spec edit).

## Custom commands — Claude Code ↔ Cursor sync

Hand-authored slash commands live in **both** `.claude/commands/*.md` and `.cursor/commands/*.md`. When you create or edit one, update both copies. This does **not** apply to the OpenSpec-generated `opsx-*` / `openspec-*` command files (those are regenerated and must not be hand-edited — see § OpenSpec above).

Cursor frontmatter differs from Claude's — use this shape:

```markdown
---
name: /<cmd>
id: <cmd>
category: Workflow
description: One-line description.
---
```

Cursor does not expand `$ARGUMENTS`, so write the body with prose placeholders (`<N>`, `<PR>`) rather than `$1`-style tokens.

`AGENTS.md` is the canonical spec for what each command does. Update it first, then keep both `.claude/commands/` and `.cursor/commands/` in sync with it.

## Bash command hygiene (prevents permission prompts)

Hard rules — apply to every agent and tool that runs Bash in this repo. Violations trigger permission prompts.

### 1. Never write to or read from `/tmp/`

Use the project-local `tmp/` directory (already gitignored). For capturing build/test/lint output, prefer pipes over file redirects:

```bash
make build 2>&1 | tail -50                           # ✓ no file needed
make test 2>&1 | tail -100                           # ✓
make build 2>&1 | grep -E "error:|warning:" | head   # ✓ filtered
```

Only if the log genuinely needs to persist (e.g. for repeated grepping), tee to `tmp/`:

```bash
make build 2>&1 | tee tmp/build.log; tail -50 tmp/build.log   # ✓ tmp/ is allowlisted
```

Never use any of these patterns:

```bash
make build > /tmp/build.log 2>&1                  # ✗ prompts
cat /tmp/anything                                 # ✗ prompts
python3 /tmp/script.py                            # ✗ prompts (also see rule 4)
```

### 2. Never use `sed -i` to modify files

Use the `Edit` tool with `replace_all: true` for find/replace, or `Write` for full file rewrites. `sed -i ''` isn't safely allowlistable (it grants arbitrary file mutation), isn't portable (macOS BSD vs GNU sed), and bypasses the harness file-state tracker.

For deleting a line range, use `Read` to find the bounds, then `Edit` with the exact old/new strings.

### 3. Never use `sed -n RANGE_p FILE` to slice a file

Use the `Read` tool with `offset` and `limit`:

```
Read(path, offset=180, limit=45)   # ✓ instead of: sed -n '180,225p' FILE
```

### 4. Never write throwaway scripts to `/tmp/` or anywhere else ephemeral

If a script needs to exist, add it under `scripts/` with a matching allowlist entry. For one-off data shaping, **reach for the allowlisted primitives first** — `jq`, `awk`, `grep`/`rg`, plus auto-allowed `sort`/`uniq`/`cut`/`tr` — since those run without prompting. Only when the task genuinely exceeds them (e.g. multi-file JSONL with shell-token parsing) fall back to a heredoc piped to `python3 -`; that path is *not* allowlistable (`python3` reading arbitrary stdin is arbitrary code execution), so expect a single permission prompt each time. For string-catalog work specifically, always use `scripts/translate_catalog/*` rather than writing new ad-hoc Python.

### 5. Use exact `make` targets with pipe-to-`tail`

The allowlist permits `make build *`, `make test *`, `make format *`, `make lint-fix *`. Invoke them directly with pipe-to-`tail` for output capture:

```bash
make build 2>&1 | tail -50               # ✓
make test 2>&1 | tail -30                # ✓
make format && make lint-fix             # ✓ both allowed, no file redirect
make gate                                # ✓ all four steps, one allowlisted command
```

For the **full four-step gate**, prefer `make gate` (alias `bash scripts/gate.sh`) over chaining the targets yourself — it logs to `tmp/gate.log`, stops at the first failure, and is a single allowlisted command. Never use the subshell form `(make format && … && make test) > tmp/gate.log 2>&1; echo "EXIT=$?"`: the parens and trailing `; echo` split into segments (`(make format`, `make test) > …`, `echo …`) that match no allow entry and prompt every time.

### 6. One command per Bash call — no `${PIPESTATUS}`, no `rc=...; echo $rc`, no `|| echo "fallback"`

The harness splits compound commands at `;` / `&&` / `||` and checks each segment against the allowlist. Shell-variable assignments and `${...}` expansions don't match any allowlist pattern, so they prompt. The Bash tool already surfaces non-zero exit codes — manual exit-code capture is dead weight.

```bash
make build 2>&1 | tail -50               # ✓ tool reports exit code itself
make build 2>&1 | tee tmp/build.log      # ✓ if you need the log to persist
```

```bash
make build 2>&1 | tee tmp/build.log; rc=${PIPESTATUS[0]}; echo "exit=$rc"   # ✗ prompts
make build 2>&1 | tail -50 || echo "build failed"                            # ✗ prompts, pointless
grep -E "error:" tmp/build.log || echo "no errors"                           # ✗ prompts
```

If you need both filtered output and full output, send **two Bash calls** — don't bundle them with `;` plus echo-separators in one call.

### 7. Never prefix a command with `cd <repo-root> && …`

The Bash tool's working directory already persists at the repo root across calls. Adding `cd /Users/jimmynotjames/dev/budgets2 && …` in a compound command triggers a permission prompt every time even though the cwd is already correct.

```bash
make build 2>&1 | tail -50       # ✓ cwd is already the repo root
git status                        # ✓ same
```

```bash
cd /Users/jimmynotjames/dev/budgets2 && make build   # ✗ prompts
```

If you genuinely need to operate in a subdirectory, use an absolute path flag rather than `cd`: `git -C /some/path`, `make -C subdir`, etc.

### 8. Never hand-write a `until … sleep … done` loop to wait on CI

To wait on a GitHub Actions run, use `bash scripts/wait_ci.sh <run-id> [pr#] [poll-seconds]` (covered by the `bash scripts/*` allow entry), ideally `run_in_background=true` so the harness re-invokes the agent on completion. It polls the run to completion (with an ~80-min safety cap), then prints a step-level breakdown plus the PR's checks and mergeability.

```bash
bash scripts/wait_ci.sh 27157096793 215         # ✓ one allowlisted command
```

```bash
until s=$(gh run view 27157096793 --json status,conclusion --jq '...'); \
  [ "${s%% *}" = "completed" ]; do sleep 30; done; echo "$s"   # ✗ prompts AND foreground sleep is blocked
```

The hand-written loop splits into segments (`until s=$(…)`, `do sleep 30`, `done`) that match no allow entry, and the harness now blocks foreground `sleep` outright — so it can't run at all. `wait_ci.sh` is the only clean way to wait on CI.

### 9. Never use `nohup` — use `run_in_background: true` instead

`nohup` shifts the leading command token to `nohup`, breaking allowlist matching for the actual command. Even `nohup fastlane screenshots` does **not** match `Bash(fastlane screenshots *)`. The Bash tool's `run_in_background: true` parameter is the correct way to background long-running commands — it doesn't alter the command string, so existing allowlist entries still apply.

```bash
# ✓ Bash tool call with run_in_background: true
fastlane screenshots > tmp/capture.log 2>&1

# ✗ both prompt and are hard-blocked by the PreToolUse hook (rule 6)
nohup fastlane screenshots > tmp/capture.log 2>&1 &
nohup bash -c 'fastlane screenshots > tmp/capture.log 2>&1' &
```

This pattern is hard-blocked by the `guard_bash_hygiene.sh` hook (rule 6).

### 10. Never use `printf`/`echo` redirects to write file content — use the Write tool

`printf '%s\n' '...' > tmp/commit-msg.txt` and `echo '...' > tmp/file` create compound Bash commands whose leading token isn't in any allowlist entry, so they prompt even though `tmp/` writes and `git commit -F`/`gh pr create --body-file` are all individually allowed. The Write tool sidesteps this entirely: it has its own `Write(./**)` permission, runs as a first-class tool call (not a Bash invocation), and leaves the subsequent git/gh command as a clean standalone string that matches its allowlist entry.

```
# ✓ Write tool creates the file; Bash runs only the git/gh command (both already allowed)
Write(tmp/commit-msg.txt)   →   git commit -F tmp/commit-msg.txt
Write(tmp/pr-body.md)       →   gh pr create --title "…" --body-file tmp/pr-body.md

# ✗ compound command — printf leading token has no allowlist entry, prompts every time
printf '%s\n' 'Commit message' > tmp/commit-msg.txt && git commit -F tmp/commit-msg.txt
echo 'body' > tmp/pr-body.md && gh pr create --title "…" --body-file tmp/pr-body.md
```

### Pre-flight check

Before sending any Bash command that contains `/tmp/`, `sed -i`, `sed -n`, a one-off `python3 -c` / `python3 /tmp/...` heredoc, `${PIPESTATUS}`, `rc=$?`, or a `||`/`;`-chained fallback `echo`, a leading `cd <path> &&`, a `nohup` prefix, or a `printf`/`echo` redirect (`> file`) — **stop and rewrite it** using the rules above. The prompts are not a permission-config bug; they are the harness telling you to use a different approach.

## Commit and PR style

### Never push directly to `main`

All changes go through a PR. **Never push commits directly to `main`**, even for small fixes or config tweaks. The `pre-push` lefthook enforces this and will block the push.

GitHub Actions CI (`.github/workflows/ci.yml`, see `docs/tech-design-doc.md` §8.5) re-runs the lint/secret/translation/build/unit-test gates on every PR — server-side, so they hold even when a hook is bypassed. The full UI suite is opt-in per PR via a `/test-full` comment. When you change the local gate versions (SwiftLint/SwiftFormat/gitleaks) or the build/test scripts the CI mirrors, update `ci.yml` in the same change to keep them in lockstep. *(⏸️ Temporarily, June 2026: the macOS jobs — `build`, `unit-tests`, and the `/test-full` trigger — are disabled for Actions-budget reasons; only the ubuntu lint/secrets/i18n gates run server-side. The local four-step gate is the sole compile/test verification until issue #228 re-enables them, ~2026-07-01.)*

The correct flow: create a feature branch → commit → push the branch → open a PR → squash-merge.

**Create the branch before the first `git add`.** Run `git checkout -b u/jimmyho/claude-code/<description>` as the very first step, before staging or committing anything. Committing on `main` and then trying to move the commit to a branch requires a force-push to reset `main`, which is destructive and requires user intervention.

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

After merging, **clean up both the remote and the local branch** — deleting only the remote leaves a stale local branch behind:

```bash
gh api repos/jimmynotjames/simple-recurring-budgets/git/refs/heads/<branch-name> -X DELETE   # remote
git checkout main && git pull --ff-only                                                       # sync main
git branch -D <branch-name>                                                                   # local
git fetch --prune                                                                             # stale tracking ref
```

`git branch -D` (not `-d`) is required: after a squash-merge the local branch tip isn't an ancestor of the new `main` commit, so `-d` warns or refuses. Only run it once the PR shows as merged. `git fetch --prune` clears the stale `origin/<branch-name>` remote-tracking ref that `git pull --ff-only` leaves behind — without it the deleted branch lingers in `git branch -a`.

### PR description

**Always pass the body via `--body-file`, never inline `--body`.** Use the **Write tool** to create `tmp/pr-body.md`, then run `gh pr create --title "…" --body-file tmp/pr-body.md` as a standalone Bash call. Similarly, use the **Write tool** for `tmp/commit-msg.txt` and run `git commit -F tmp/commit-msg.txt`. Never use `printf ... > file` or `echo ... > file` to produce these files — that creates a compound Bash command whose leading token (`printf`/`echo`) has no allowlist entry and will prompt (see hygiene rule 10). PR bodies and commit messages that contain backticks, newlines, or `$` characters also can't safely be inlined via `--body` or `-m`.

```markdown
Closes #N
## What
* <area of change (complete / partial — what's still pending)>
## Why
<one sentence — the user problem or product goal>
## Test plan
- [ ] <golden path>
- [ ] <edge case if non-obvious>
## Tools
- <Tool or model> — <one-liner if role isn't obvious>
```

- **What:** one bullet per meaningful area of change, not per file. Note if a feature is partial.
- **Why:** one sentence — the motivation reviewers can't get from the diff.
- **Test plan:** lightweight sanity check, 2–3 bullets max.
- **Tools:** name AI tools/models used (e.g. `Claude Code (Sonnet 4.6)`); one-liner only when helpful.
- **Issue linkage:** `Closes #N` for a complete fix (auto-closes on squash-merge to `main`); `Refs #N` + pending note for partial; omit if no issue.

## Issue-driven workflow

Standing loop for turning a GitHub issue into a merged fix. `/create-pr-for-issue` and `/merge-pr` automate the two halves. **Never merge on the same turn the PR is opened.**

**Front half — issue to open PR** (`/create-pr-for-issue <N>`):

1. **Read the issue** — `gh issue view <N>` (add `--comments` if the thread is substantive). Restate the problem and intended fix in a sentence or two before writing code.
2. **Branch** — `u/jimmyho/claude-code/<short-description>` per the branch-name convention above, off the latest `main`.
3. **Fix** — implement in code. If the change alters product behavior, specs, or the data model, drive it through OpenSpec (`/opsx:propose` → `/opsx:apply`) rather than hand-editing specs, and honor the cross-cutting checklist (§ Cross-cutting concerns) for any UI-touching change.
4. **OpenSpec verify** — if the fix went through OpenSpec, run `/opsx:verify` and fix everything it flags autonomously. Always run it, even if `/opsx:apply` already verified — apply's check is not a substitute.
5. **Fresh-eye code review** — review the full branch diff with fresh eyes and fix what you find autonomously: correctness bugs, architectural problems, and serious future-extensibility risks (not style nits the linter owns). Exercise best judgment; only stop to ask the user when a finding genuinely needs their call. Runs **after** the OpenSpec verify in step 4.
6. **Verify** — the four-step order: `make format` → `make lint-fix` → `make build` → `make test`. Re-run after any step-4/5 fixes so the PR opens green.
7. **Archive the OpenSpec change (if any) — when confident** — if the fix went through OpenSpec **and** you're confident the front-half work fully meets expectations, finish the OpenSpec lifecycle **in this same branch, before opening the PR**: run `/opsx:archive <name>`, which syncs the change's delta specs into the main specs and moves the change to `openspec/changes/archive/<date>-<name>/` (auto-syncs per § OpenSpec > Skill behavior overrides). Archive is markdown-only (spec sync + a directory move), so it needs no build/test re-run. **Hold off when confidence is incomplete** — e.g. you've asked the user to manually verify behavior you can't test yourself, or the change is complex enough that review is likely to change it. In that case leave the change active, note in the PR body that the OpenSpec archive is **intentionally deferred to merge time**, and the back-half pre-merge check (step 11) will prompt to complete it once the work is confirmed. Either way the archive ships in the **same** PR as the code — never a follow-up PR.
8. **Open the PR** — push the branch and `gh pr create`, body per the PR-description template, including issue linkage: `Closes #<N>` for a complete fix, or `Refs #<N>` plus a "what's still pending" note for a partial one.
9. **Stop for review.** Report the PR URL and hand back. Merging waits for an explicit go-ahead from the user.

**Back half — merge and resolve** (`/merge-pr <PR>`), only after the user says to land it:

10. **Wait for CI, then confirm it's safe to merge** — `gh pr view <PR>` and `gh pr checks <PR>`. If any check is still pending/queued, wait for completion with `gh pr checks <PR> --watch` run **in the background** (the harness re-invokes on completion; never a hand-rolled sleep loop — § Bash command hygiene #8). This step is the **only** CI gate: `main` has no GitHub branch protection, so `gh pr merge` would happily land a red or still-running PR. If any check fails or the PR isn't mergeable, stop and report instead of merging.
11. **Pre-merge OpenSpec check** — before merging, confirm the OpenSpec lifecycle for any change tied to this PR is complete. It is **either** already archived in this PR (front-half step 7) **or** intentionally deferred to now (front-half step 7 held off because confidence was incomplete — pending manual verification, complexity). Verify with `openspec list` and the PR diff. **If archiving — or any other OpenSpec step (unsynced delta specs, incomplete tasks/artifacts) — is still pending, do NOT merge: stop, tell the user exactly which step is pending, and ask whether to complete it now** (this is the expected path for a deferred archive — confirm the work is now validated, then proceed). If the user says yes, perform it on the **PR's branch** (check out the branch if needed, sync + `/opsx:archive`, then push so it lands in this same PR), then continue to merge. This prompt is required, and it keeps the archive in the same PR rather than spawning a follow-up.
12. **Check for spec drift from workshopping** — if the PR was workshopped during review after the change was archived (review-time changes to behavior, specs, or the data model that the already-archived/synced specs don't reflect), the archived change and `openspec/specs/` may have drifted from what's actually shipping. **Stop and ask the user** whether to update the OpenSpec docs (the archived change's delta specs / design / tasks) and re-sync the main specs before merging. If yes, edit the change in place under `openspec/changes/archive/<date>-<name>/` and re-run the spec sync, all on the PR's branch so it lands in this same PR. Like step 11, this prompt is a deliberate exception to the "don't prompt during workflows" default — surface the drift rather than merging specs that no longer match the code.
13. **Merge & clean up** — `gh pr merge --squash` (one PR = one commit on `main`), then delete **both** the remote branch (allowlisted `gh api … -X DELETE`) and the local branch (`git checkout main && git pull --ff-only && git branch -D <branch>`), and run `git fetch --prune` to clear the stale tracking ref. Deleting only the remote leaves a stale local branch — see § Merging.
14. **Resolve the issue** — confirm state with `gh issue view <N> --json state,stateReason`:
   - **Complete fix** — the closing keyword auto-closes it on merge. If it's somehow still open, close explicitly: `gh issue close <N> --comment "Fixed in #<PR>."`.
   - **Partial fix** — the issue stays open by design; comment a pointer: `gh issue comment <N> --body "Partially addressed by #<PR>. Still pending: <summary>."`.

No CI workflow or git hook is involved — closure rides on GitHub's native closing-keyword behavior plus the post-merge verification in step 14.
