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

Each clone gets its own dedicated simulator (name derived from repo path, e.g. `iPhone 17 [a1b2c3d4]`) created and managed automatically — no manual setup needed for a normal build/test run. The UI pass runs in two phases: pass 1 skips XCUITest to warm the sim; pass 2 runs `AccessibilityAuditTests`, `UserJourneyTests`, and `ClearAmountButtonUITests`. XCUITest targets use XCTestCase with `continueAfterFailure = false` (Swift Testing is not supported in XCUITest bundles).

For management commands (`make initialize-sims`, `make sim-clean`, etc.), `SRB_SIM_MAX` concurrency tuning, the AM/PM 24h time workaround, and clone-risk context, invoke the **`ios-sims` skill**.

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
- **Mixpanel events** — new user-initiated actions that materially change app state (new destructive action, new CTA, new toggle affecting usage or retention) must fire the corresponding `AnalyticsClient.track(...)` event per [`docs/analytics-spec.md`](docs/analytics-spec.md). No PII; respect consent. Boundary with OSLog: `docs/analytics-spec.md` §17. **Keep the spec's catalog in sync:** any change to *what* is emitted — a new/changed event, a property added to or removed from an existing event, **a new value in a categorical property's enum** (e.g. a new `BudgetPeriod`/`period` value, or a new `icloud_state`), changed bucket boundaries, or a new super/people property — must update `docs/analytics-spec.md` §9–§10 in the same change, with a Revision-History entry. (Adding an enum value to an already-instrumented property ships no new action, so the "fire `track(...)`" rule alone won't catch it.)
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

## Fork, secrets, and branding

Secrets and branding policy for contributors and forks lives in [`CONTRIBUTING.md`](CONTRIBUTING.md). Key points for agents:

- **Out-of-repo secrets:** `config/Secrets.local.xcconfig` (gitignored). Never read or commit it; use `config/Secrets.xcconfig` placeholder defaults only for key-name reference.
- **Ship guard:** `scripts/verify_release_secrets.sh` blocks Release archives and `fastlane beta` / `fastlane release` when placeholder sentinels remain. Do not bypass without `SKIP_RELEASE_SECRETS_CHECK=1`.
- **Branding:** do not alter the Wren app icon, name, or store metadata as part of code changes. See [`TRADEMARK.md`](TRADEMARK.md).

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

**Route every branch/commit/PR/merge through the skills — don't hand-roll the pipeline.** The skills are the canonical step-by-step spec (review, gate, PR body, branch cleanup, issue linkage):

- **Issue → PR → merge:** `/create-pr-for-issue <N>` then `/merge-pr <PR>`.
- **Code already written, no issue:** `/create-pr` then `/merge-pr <PR>`.
- **TestFlight build:** `/appstore:push-testflight-build` (branch → build → upload → PR → CI → merge, fully automated).

**Never merge on the same turn the PR is opened.**

### Conventions

These govern *every* commit — including ad-hoc ones not run through a skill — and the skills cite them rather than restating:

- **Never push to `main`.** Branch first: `git checkout -b u/jimmyho/<tool>/<kebab-description>` **before the first `git add`** (moving a commit off `main` later needs a destructive force-push). `<tool>` documents authorship — `claude-code` for Claude Code, `+` to combine (`cursor+claude`); omit for manual branches. Description is lowercase kebab-case, no underscores. The `pre-push` lefthook enforces the no-`main` rule.
- **Commit/PR subject:** `<Past-tense verb> <description>.` — sentence case, ends with a period, **≤72 chars**, no conventional-commit prefix (`feat:`/`fix:`/`chore:`). Match the verb's weight to the change (`Implemented` a feature, not `Updated`). The PR number `(#N)` goes at the end of the commit subject.
- **Commit body** (optional for one-liners; required when a PR spans more than one area): `*` bullets naming **areas of change** (feature/refactor, not files), a one-sentence `Why:` line the diff can't show, and the `Co-Authored-By:` footer on Claude commits.
- **PR body:** write to `tmp/pr-body.md` (Write tool) then `gh pr create --body-file` — never inline `--body` (hygiene rule 10). Structure per `.github/pull_request_template.md`. Linkage: `Closes #N` (complete fix, auto-closes on squash-merge), `Refs #N` + pending note (partial), or omit.
- **Squash-merge only** — one PR = one commit on `main`.

### CI lockstep

GitHub Actions CI (`.github/workflows/ci.yml`, see `docs/tech-design-doc.md` §8.5) re-runs the lint/secret/translation/build/unit-test gates server-side on every PR, so they hold even when a hook is bypassed; the full UI suite is opt-in via a `/test-full` comment. When you bump local gate versions (SwiftLint/SwiftFormat/gitleaks) or the build/test scripts CI mirrors, update `ci.yml` in the same change.
