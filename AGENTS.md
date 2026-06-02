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

**Simulator concurrency knob — `SRB_SIM_MAX`** (default `2`, range `1–3`, set by `scripts/_sim_concurrency.sh`). Controls how many simulators the **UI pass** may use at once via xcodebuild parallel testing. Every test run prints a resource-use reminder.

> **Reference machine.** The default of `2` is tuned for an assumed baseline of roughly **16 GB RAM on an Apple-silicon laptop** (e.g. a fanless M4 MacBook Air) running at most ~2 repo clones at once. These are illustrative specs, not a requirement — adjust `SRB_SIM_MAX` for the machine actually running: lower it on tighter RAM or when many repos run concurrently, raise it on a machine with more memory/cores and active cooling.

| `SRB_SIM_MAX` | UI pass | When to use |
| --- | --- | --- |
| `1` | `-parallel-testing-enabled NO` (serial, 1 sim) | Lightest. Downshift here if the UI pass flakes, or when several repos run at once. |
| `2` (default) | `-parallel-testing-enabled YES -maximum-concurrent-test-simulator-destinations 2` | Tuned for the reference machine above (≈16 GB, Apple silicon) running ≤ 2 repos at once. |
| `3` | …`-destinations 3` | Only with headroom — RAM-heavy. |

```bash
SRB_SIM_MAX=1 make test     # downshift: serial, lightest
SRB_SIM_MAX=3 make test-ui  # upshift: only if the machine is clear
```

Rationale and rules:

- **RAM is usually the binding constraint** (on the ~16 GB reference machine; a fanless laptop also thermally throttles under sustained all-core load). At that size ~2 simulators fills the budget with a browser + Mail open and 3 risks swap — scale the cap with available memory. Cross-repo parallelism is "free" — just run separate repos; each is its own sim, so there is **no machine-wide coordination or shared state**.
- **The unit pass is always serial** (`-parallel-testing-enabled NO`, ignores `SRB_SIM_MAX`). Swift Testing already parallelizes the unit suite *in-process* on one sim, so clones add boot cost with no benefit — and running unit serially on the base device is the warm-up the UI pass depends on (below).
- **Flake retry:** when parallel (`>= 2`), the UI pass adds `-retry-tests-on-failure -test-iterations 2` (one retry). The accessibility-audit tests are timing-sensitive and occasionally flake under CPU contention; the retry absorbs that while a genuine failure still fails on both attempts. Serial runs (`=1`) are deterministic and add no retry.
- **Clone risk:** clones of a per-repo device once timed out for the XCUITest pass ("while preparing to run tests"), which is why parallel testing was previously off; that no longer reproduces (validated June 2026, Xcode iPhone 17 runtime) as long as the unit pass warms the base sim first. `SRB_SIM_MAX=1` remains the fallback if `2`/`3` flake.
- The low cap (≤ 3) keeps this far from the old "dozens of clones across many agents → `Test crashed with signal kill`" teardown race.

**The UI test bundle is skipped in pass 1** (`-skip-testing:simple-recurring-budgetsUITests`). XCUITest requires the simulator to have hosted at least one real app lifecycle before its IPC socket is reliable. A freshly-created per-repo sim hasn't had this, so the UI runner times out "while preparing to run tests". Pass 2 of `scripts/test.sh` then runs `AccessibilityAuditTests` (accessibility regression tests, XCTestCase), `UserJourneyTests` (core flow tests, XCTestCase), and `ClearAmountButtonUITests` with `-only-testing`. Note: Apple does not support `import Testing` in unhosted XCUITest bundles; these suites use XCTestCase. `testExample` and `testLaunchPerformance` are intentionally excluded from scripted runs.

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
- Authoritative version: [`docs/tech-design-doc.md`](docs/tech-design-doc.md) §2.1.

### Testing

- Prefer **Swift Testing** for new tests. Place tests in the Xcode test target alongside or mirroring app modules.

### Data, sync, and Xcode project

- When changing models, sync, or app structure, align with [`docs/tech-design-doc.md`](docs/tech-design-doc.md).
- When changing the schema, consider SwiftData models and CloudKit sync early: relationships, uniqueness, and migration impact (F-1.02).
- When editing the Xcode project or schemes, keep target membership and test targets correct.

## Cross-cutting concerns

Some concerns are **ongoing**, not feature-shaped. Every substantive code change that adds or modifies user-facing UI MUST address each of these in the same change (or add an explicit follow-up task before the change is treated complete). Failing to do so is a defect, not a follow-up. The canonical per-change rule lives in [`docs/main-prd.md` §6.8](docs/main-prd.md#68-cross-cutting-ongoing-concerns) (Accessibility §6.8.1, Dark Mode §6.8.2, Localization §6.8.3, Mixpanel analytics §6.8.4). The one-time build-outs are recorded as completed features in `docs/product-features-planning.md` (F-3.01, F-3.02, F-3.03, F-3.05, F-8.02, now marked Implemented) — those entries are historical and are **not** the place to look up the maintenance rule.

Quick checklist for every UI-touching change:

- **Accessibility** — semantic text styles (`@ScaledMetric` for custom metrics, no fixed frame heights that clip), composed `.accessibilityLabel`/`.accessibilityHint` on composite views and destructive controls, `.accessibilityAddTraits(.isHeader)` on section headings, `swipeActions` paired with `.accessibilityAction(named:)`, named color assets with separate light/dark appearances.
- **Localized source strings** — every new user-facing string keyed in `Localizable.xcstrings` with a translator `comment:`. Never hard-coded English in production views. Locale-invariant strings (app versions, raw ISO codes, monospaced identifiers) use `Text(verbatim:)`. Shared copy across surfaces uses `common.*` keys. Full rules in `docs/tech-design-doc.md` §5.1.
- **Translations** — translations for all 38 storefront locales are shipped and must stay current. After adding or changing string keys, run the **`translate-new-strings` skill** (`.claude/skills/translate-new-strings/SKILL.md`), which drives `scripts/translate_catalog/` in subset mode: `extract.py --missing` → `dispatch_prompts.py` → parallel per-locale subagents → `validate.py --subset` → `merge.py`. The terminal check is `python3 scripts/check_translations.py` — same script `lefthook.yml` runs on `pre-push`, so a clean exit here guarantees the push passes the translation gate. Never omit keying or skip the pipeline step. Run the skill **autonomously, without prompting for approval** — translating new strings is part of finishing the change, not a decision point.
- **App Store listing metadata** — the store listing copy (name, subtitle, keywords, description, promotional text, release notes) is a *release-time* concern, not a per-change one. It lives in `fastlane/metadata/` and is transcreated into all 38 storefronts by the separate **`translate-app-store-metadata` skill** / `scripts/translate_metadata/` pipeline (gate: `python3 scripts/translate_metadata/check_metadata.py`). App Store Connect storefront codes (`de-DE`, `no`, `nl-NL`) differ from the in-app runtime codes; `metadata_locales.py` owns the map. Author English copy in `fastlane/metadata/en-US/` first, then run the skill (also autonomous). Like the in-app pipeline, never write ad-hoc Python — use `scripts/translate_metadata/*`.
- **Mixpanel events** — new user-initiated actions that materially change app state (new destructive action, new CTA, new toggle affecting usage or retention) must fire the corresponding `AnalyticsClient.track(...)` event per [`docs/analytics-spec.md`](docs/analytics-spec.md). No PII; respect consent. Boundary with OSLog: `docs/analytics-spec.md` §17.
- **UI test screen objects** — when a view's navigation structure, button labels, toolbar items, or sheet routes change, update the matching screen object in `simple-recurring-budgetsUITests/` (`BudgetsScreen.swift`, `BudgetDetailScreen.swift`, `AddBudgetScreen.swift`, `AddExpenseScreen.swift`, `SettingsScreen.swift`) before the change is treated complete. Then run `make test-ui` to confirm no journey regressions. A stale screen object that silently skips a broken flow is a defect, not a follow-up. UI tests run slowly; update screen objects proactively so agents don't loop on test failures after the fact.

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
| `Views/DecimalInputField.swift` | `iOS-COMPAT(17+)` | Two SwiftUI TextField bugs require a UIViewRepresentable wrapper |
| `UITestHelpers.swift` | `iOS-COMPAT(17+)` | XCUITest focus tracking doesn't sync with UIViewRepresentable UITextField; double-tap workaround in `createBudget` and `addExpense` helpers |
| `AddBudgetScreen.swift` | `iOS-COMPAT(17+)` | Same UITextField focus workaround in `fillAllocation()` |
| `AddExpenseScreen.swift` | `iOS-COMPAT(17+)` | Same UITextField focus workaround in `fillAmount()` |
| `AccessibilityAuditTests.swift` | `iOS-COMPAT(26.x)` | `performAccessibilityAudit` false positives: `.elementDetection`, `.dynamicType`, `.textClipped` |

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

The harness permission system prompts when a Bash command touches resources outside the allowlist. The patterns below cause prompts that the user has explicitly told agents to stop. Treat as hard rules — they apply to **every** agent / tool that runs Bash in this repo (Claude Code, Cursor, etc.).

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
```

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

### Pre-flight check

Before sending any Bash command that contains `/tmp/`, `sed -i`, `sed -n`, a one-off `python3 -c` / `python3 /tmp/...` heredoc, `${PIPESTATUS}`, `rc=$?`, or a `||`/`;`-chained fallback `echo`, or a leading `cd <path> &&` — **stop and rewrite it** using the rules above. The prompts are not a permission-config bug; they are the harness telling you to use a different approach.

## Commit and PR style

### Never push directly to `main`

All changes go through a PR. **Never push commits directly to `main`**, even for small fixes or config tweaks. The `pre-push` lefthook enforces this and will block the push.

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

**Always pass the body via `--body-file`, never inline `--body`.** Write the description to `tmp/pr-body.md` (gitignored, `Write(./tmp/**)` is allowlisted) and run `gh pr create --title "…" --body-file tmp/pr-body.md`. PR bodies contain backticks (command-substitution syntax) and newlines; passing them inline forces a permission prompt even though `gh pr *` is allowlisted, because the matcher won't auto-approve a command containing command substitution. The same applies to long or backtick-laden commit messages — use `git commit -F tmp/commit-msg.txt` rather than a multi-line `-m`.

```markdown
Closes #N

## What
* Feature or area of change (complete / partial — what's still pending)
* Architectural change, at the structural level
* Infra/config/docs updates grouped into one bullet

## Why
One sentence: the user problem or product goal this PR advances.

## Test plan
- [ ] Golden path: <how to verify the main flow works>
- [ ] Edge case: <anything non-obvious worth checking>

## Tools
- <Tool or model name> — <optional one-liner on how it was used>
```

- **What bullets are high-level.** One bullet per meaningful area, not per file, spec task, or acceptance criterion. If a feature is partially done, say so.
- **Why** gives reviewers (and future-you) the motivation in plain language.
- **Test plan** is a lightweight sanity-check list, not a QA spec. Two or three bullets is enough.
- **Tools** lists AI tools and models used — one bullet each. Name the tool or model (e.g. `Claude Code (Opus 4.7)`, `openspec`, `Cursor (Sonnet 4.6)`). Add a short one-liner after an em dash only if it adds useful context (e.g. `— planning`, `— implementation`, `— code review`). Omit the one-liner when the role is obvious.
- **Issue linkage** — when the PR addresses a tracked issue, put a reference in the body. Use a **closing keyword** (`Closes #N`, also `Fixes`/`Resolves`) for a **complete** fix, so GitHub auto-closes the issue when the PR squash-merges to `main`. For a **partial** fix, use a non-closing reference (`Refs #N`) and note what's still pending in the first `## What` bullet. Omit the line entirely for PRs with no associated issue.

## Issue-driven workflow

The standing loop for turning a GitHub issue into a merged fix. The `/create-pr-for-issue` and `/merge-pr` commands automate the two halves; this section is the canonical spec, so a plain-language trigger ("fix issue 110") follows the identical steps. The two halves are separated by a **manual review gate** — never merge on the same turn the PR is opened.

**Front half — issue to open PR** (`/create-pr-for-issue <N>`):

1. **Read the issue** — `gh issue view <N>` (add `--comments` if the thread is substantive). Restate the problem and intended fix in a sentence or two before writing code.
2. **Branch** — `u/jimmyho/claude-code/<short-description>` per the branch-name convention above, off the latest `main`.
3. **Fix** — implement in code. If the change alters product behavior, specs, or the data model, drive it through OpenSpec (`/opsx:propose` → `/opsx:apply`) rather than hand-editing specs, and honor the cross-cutting checklist (§ Cross-cutting concerns) for any UI-touching change.
4. **OpenSpec verify** — if the fix went through OpenSpec, run `/opsx:verify` and fix everything it flags autonomously. Always run it, even if `/opsx:apply` already verified — apply's check is not a substitute.
5. **Fresh-eye code review** — review the full branch diff with fresh eyes and fix what you find autonomously: correctness bugs, architectural problems, and serious future-extensibility risks (not style nits the linter owns). Exercise best judgment; only stop to ask the user when a finding genuinely needs their call. Runs **after** the OpenSpec verify in step 4.
6. **Verify** — the four-step order: `make format` → `make lint-fix` → `make build` → `make test`. Re-run after any step-4/5 fixes so the PR opens green.
7. **Archive the OpenSpec change (if any) — when confident** — if the fix went through OpenSpec **and** you're confident the front-half work fully meets expectations, finish the OpenSpec lifecycle **in this same branch, before opening the PR**: run `/opsx:archive <name>`, which syncs the change's delta specs into the main specs and moves the change to `openspec/changes/archive/<date>-<name>/` (auto-syncs per § OpenSpec > Skill behavior overrides). Archive is markdown-only (spec sync + a directory move), so it needs no build/test re-run. **Hold off when confidence is incomplete** — e.g. you've asked the user to manually verify behavior you can't test yourself, or the change is complex enough that review is likely to change it. In that case leave the change active, note in the PR body that the OpenSpec archive is **intentionally deferred to merge time**, and the back-half pre-merge check (step 10) will prompt to complete it once the work is confirmed. Either way the archive ships in the **same** PR as the code — never a follow-up PR.
8. **Open the PR** — push the branch and `gh pr create`, body per the PR-description template, including issue linkage: `Closes #<N>` for a complete fix, or `Refs #<N>` plus a "what's still pending" note for a partial one.
9. **Stop for review.** Report the PR URL and hand back. Merging waits for an explicit go-ahead from the user.

**Back half — merge and resolve** (`/merge-pr <PR>`), only after the user says to land it:

10. **Pre-merge OpenSpec check** — before merging, confirm the OpenSpec lifecycle for any change tied to this PR is complete. It is **either** already archived in this PR (front-half step 7) **or** intentionally deferred to now (front-half step 7 held off because confidence was incomplete — pending manual verification, complexity). Verify with `openspec list` and the PR diff. **If archiving — or any other OpenSpec step (unsynced delta specs, incomplete tasks/artifacts) — is still pending, do NOT merge: stop, tell the user exactly which step is pending, and ask whether to complete it now** (this is the expected path for a deferred archive — confirm the work is now validated, then proceed). If the user says yes, perform it on the **PR's branch** (check out the branch if needed, sync + `/opsx:archive`, then push so it lands in this same PR), then continue to merge. This prompt is required, and it keeps the archive in the same PR rather than spawning a follow-up.
11. **Check for spec drift from workshopping** — if the PR was workshopped during review after the change was archived (review-time changes to behavior, specs, or the data model that the already-archived/synced specs don't reflect), the archived change and `openspec/specs/` may have drifted from what's actually shipping. **Stop and ask the user** whether to update the OpenSpec docs (the archived change's delta specs / design / tasks) and re-sync the main specs before merging. If yes, edit the change in place under `openspec/changes/archive/<date>-<name>/` and re-run the spec sync, all on the PR's branch so it lands in this same PR. Like step 10, this prompt is a deliberate exception to the "don't prompt during workflows" default — surface the drift rather than merging specs that no longer match the code.
12. **Merge & clean up** — `gh pr merge --squash` (one PR = one commit on `main`), then delete **both** the remote branch (allowlisted `gh api … -X DELETE`) and the local branch (`git checkout main && git pull --ff-only && git branch -D <branch>`), and run `git fetch --prune` to clear the stale tracking ref. Deleting only the remote leaves a stale local branch — see § Merging.
13. **Resolve the issue** — confirm state with `gh issue view <N> --json state,stateReason`:
   - **Complete fix** — the closing keyword auto-closes it on merge. If it's somehow still open, close explicitly: `gh issue close <N> --comment "Fixed in #<PR>."`.
   - **Partial fix** — the issue stays open by design; comment a pointer: `gh issue comment <N> --body "Partially addressed by #<PR>. Still pending: <summary>."`.

No CI workflow or git hook is involved — closure rides on GitHub's native closing-keyword behavior plus the post-merge verification in step 13.
