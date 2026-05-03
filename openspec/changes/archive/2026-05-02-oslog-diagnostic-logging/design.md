## Context

[`docs/product-features-planning.md`](../../../docs/product-features-planning.md) F-8.01 ("Diagnostic logging via OSLog") is partially implemented:

- [`simple-recurring-budgets/Logging/AppLoggers.swift`](../../../simple-recurring-budgets/Logging/AppLoggers.swift) defines three category constants — `Logger.bootstrap`, `Logger.cloudKit`, `Logger.ui` — keyed off the bundle identifier subsystem.
- Four `Logger.cloudKit` call sites exist in `makeProductionModelContainer` inside `simple_recurring_budgetsApp.swift`: `cloudkit.container.backed`, `cloudkit.container.localFallback`, `cloudkit.container.localSuccess`, `cloudkit.container.failed`.
- `Logger.bootstrap` and `Logger.ui` have **zero** call sites.
- No structural rule exists in the codebase or in `openspec/specs/` to keep future contributors from (a) bypassing the `privacy:` argument when interpolating user-derived values, (b) adding a route from `Logger.*` into `AnalyticsClient` (or vice versa) that would violate [`docs/analytics-spec.md` §17](../../../docs/analytics-spec.md), or (c) drifting the `AppLoggers` category list out of sync with `docs/tech-design-doc.md` §7.

The boundary between OSLog (diagnostic, on-device only) and `AnalyticsClient` / Mixpanel (product, off-device) is a **product** constraint set by [`docs/main-prd.md`](../../../docs/main-prd.md) §6.3 ("Protect user's privacy with the usual Apple tools") and operationalized by [`docs/analytics-spec.md`](../../../docs/analytics-spec.md) §§5, 8, and 17. F-8.01 is the OSLog half of that split and SHOULD ship before F-8.02 so the boundary is established before any Mixpanel call site is added (per F-8.01's own "Edge Cases / Notes" entry).

## Goals / Non-Goals

**Goals**

- Add the missing `Logger.bootstrap` and `Logger.ui` call sites so F-8.01's acceptance criteria are met verbatim.
- Add the `Logger.cloudKit` call site for `CKAccountChanged` transitions in `SettingsView` so all three categories have at least one observable diagnostic entry.
- Codify the privacy contract (`.public` vs `.private`) and the boundary contract with `AnalyticsClient` as a first-class capability spec (`diagnostic-logging`) so future call sites are guarded by the spec, not by tribal knowledge.
- Land Swift Testing coverage that asserts the **structural** invariants — categories exist with the expected names; the `AnalyticsClient` API surface contains no helper that consumes a `Logger.*` callback or vice versa.
- Update `docs/tech-design-doc.md` §7 in the same change so the doc-update protocol from `openspec/config.yaml` and `AGENTS.md` is honored.

**Non-Goals**

- **Read-back assertions on `OSLog`-emitted log lines.** `OSLogStore` reads are brittle in CI (sandbox restrictions, simulator vs device asymmetry, retention policies), and this change's contract is structural, not behavioral. The risk of a missed call-site emission is mitigated by code-review against the spec, not by runtime assertions.
- **Adding `Logger.ui` call sites for non-destructive UI traces** (Add Expense success, Add Budget success, Settings open, sheet presents). F-8.01 acceptance criteria explicitly say "No entries for non-destructive UI traces in Phase 1 — leaner logging by default."
- **Telemetry signposts (`os_signpost`) or performance traces.** F-8.01 is opt-in unified logging only.
- **Extending the category list.** `bootstrap`, `cloudKit`, and `ui` are the canonical three per `AppLoggers.swift` and `docs/tech-design-doc.md` §7. New categories require a separate change.
- **Refactoring the existing four `Logger.cloudKit` call sites** in `makeProductionModelContainer`. They satisfy F-8.01 already; touching them creates churn for no contract gain.
- **Anything in `AnalyticsClient` / `MixpanelAnalyticsClient`.** That is F-8.02's surface. This change only asserts the negative — that no API exists in `AnalyticsClient` to consume a `Logger.*` callback.

## Decisions

### D1. New capability spec `diagnostic-logging` (cross-cutting, single owner)

**Decision.** Create one new capability spec at `openspec/specs/diagnostic-logging/spec.md` that owns the OSLog contract end-to-end: the three categories, every required call site, the privacy levels, and the structural boundary with `AnalyticsClient`.

**Alternatives considered.**

- *Spread the requirements across existing capability specs.* The bootstrap site lives in `simple_recurring_budgetsApp` (no existing spec), the CloudKit site lives in `SettingsView` (`settings-screen` spec), and the four `ui` sites live across `budget-detail-screen` and `add-edit-budget-screen` specs. Distributing four small log-emit requirements into 3–4 different specs makes the privacy contract un-discoverable: a future contributor adding a destructive action under a new screen would have no central spec to consult.
- *Embed the contract in `docs/tech-design-doc.md` only.* §7 already names the categories, but `tech-design-doc.md` is non-normative architectural prose — it doesn't have testable scenarios, and OpenSpec changes don't carry deltas against it. We need a spec contract for the structural test in §D6 to anchor against.

**Rationale.** Diagnostic logging is a cross-cutting concern; one cohesive spec is easier to extend and to verify. Future features that add a `Logger.*` call site update one spec, not several. The screen-level specs (`budget-detail-screen`, `settings-screen`, `add-edit-budget-screen`) remain focused on user-observable behavior; they don't need to mention `Logger.*` because nothing user-observable changes.

### D2. Bootstrap call site — placement and level

**Decision.** Emit a single `info`-level entry from `simple_recurring_budgetsApp.init()` (or as a dedicated helper called from `init`), after the `ModelContainer` has been resolved, recording `appDatabaseLaunchMode` (Release: always `.normal`; DEBUG: the active case from the dev override). Privacy `.public` for the enum value.

**Alternatives considered.**

- *Emit from `body`'s `.task`.* Defers logging until the first WindowGroup attaches, which is later than necessary and would race the `Logger.cloudKit` container-creation entries that F-8.01 wants ordered before the bootstrap line in the unified log timeline (the `cloudKit` lines fire from `makeProductionModelContainer`, which `init()` calls, so they precede any `init()`-emitted bootstrap line — that order is desirable for "what backed the container" → "and here's the launch mode that drove it").
- *Multiple bootstrap lines (e.g., one for the launch mode, another for "container ready").* F-8.01 explicitly says "a **single** `info`-level entry on app launch." Honor the AC.

**Rationale.** `init()` is the earliest deterministic point where the launch mode is known, and the `Logger.cloudKit` lines emitted from `makeProductionModelContainer` are part of `init()`'s flow. The `bootstrap` line lands once per launch, after CloudKit resolution, with the launch mode as the static enum value.

### D3. CloudKit account-status transition log site

**Decision.** Inside `SettingsView.loadICloudStatus()`, after the `accountStatus` field is updated, emit a `Logger.cloudKit.notice` entry only if the value changed (`old != new`). The line records the two enum case names (e.g., `"cloudkit.account.transition: checking → available"`) with privacy `.public` — values are static enums (`.checking`, `.available`, `.unavailable`), never the user's iCloud identity.

**Alternatives considered.**

- *Emit on every `loadICloudStatus()` call regardless of transition.* Spammy on background app activations where the status hasn't moved. Filtering on transition keeps the unified log readable and matches F-8.01's "leaner logging by default" stance.
- *Emit from inside `observeAccountChanges()` instead of `loadICloudStatus()`.* `loadICloudStatus()` is the funnel — both the initial fetch and every notification-driven refresh go through it, so logging there covers both code paths with one line.

**Rationale.** F-8.01 AC says "an entry on `CKAccountChanged` notification reception in `SettingsView` that records the old → new account status transition." Filtering on `old != new` is the literal reading of "transition" and avoids noise.

### D4. UI destructive-action log sites — five lines, four destructive operations

**Decision.** Emit one `Logger.ui.debug` entry per destructive call site, recording the entity's `persistentModelID` (privacy `.private`) and a static action name string (privacy `.public`):

| Action            | Call site                                                          | Entity ID logged       |
| ----------------- | ------------------------------------------------------------------ | ---------------------- |
| `Reset Budget`    | `BudgetDetailView.resetBudget`                                     | `budget.persistentModelID` |
| `Reset Carry-Over`| `BudgetDetailView.resetCarryOver`                                  | `budget.persistentModelID` |
| `Delete Budget`   | `AddEditBudgetViewModel.delete(context:)` (Edit-mode confirm path) | `budget.persistentModelID` |
| `Delete Expense`  | `BudgetDetailView+ExpenseSection.deleteExpense(_:)` (single funnel for both swipe and rotor paths) | `expense.persistentModelID` |

`persistentModelID` is `Hashable` and `CustomStringConvertible`; interpolating it via `\(budget.persistentModelID, privacy: .private)` produces a redacted token in Release builds and a readable identifier when the device is attached to Console.app for debugging.

**Alternatives considered.**

- *Log the entity's `name` instead of `persistentModelID`.* `Budget.name` is user-typed free text; it is `.private` per [`docs/analytics-spec.md` §5](../../../docs/analytics-spec.md) on the analytics side and the same privacy logic applies on the OSLog side. `persistentModelID` is a stable, opaque token suitable for cross-referencing log lines without leaking copy.
- *Two log lines for `Delete Expense` (one in `swipeActions`, one in the rotor `accessibilityAction`).* They both call the same `deleteExpense(_:)` method; logging at the funnel produces one canonical line per logical delete.
- *Emit at `info` instead of `debug`.* `info` is appropriate for `bootstrap` (per-launch, low frequency); `debug` is appropriate for `ui` because destructive actions are user-frequency events that we don't need persisted in the system log archive. F-8.01 AC explicitly specifies "`debug`-level."

**Rationale.** Maps F-8.01 AC to the four existing call sites with the lowest possible code surface. The shared `deleteExpense(_:)` funnel for swipe + rotor is an existing pattern in the view (per [`docs/audits/localization+voiceover-audit-2026-04-30.md`](../../../docs/audits/localization+voiceover-audit-2026-04-30.md)) — log there.

### D5. Privacy-level rule — explicit `privacy:` always

**Decision.** Codify in the `diagnostic-logging` spec: every `Logger.*` call site that interpolates a value MUST set an explicit `privacy:` argument. Static string literals with no interpolation (e.g., `Logger.cloudKit.info("cloudkit.container.backed")`) do NOT need a `privacy:` argument because there is no value to redact.

Mapping for this change's call sites:

- **Bootstrap launch mode** — `.public` (`AppDatabaseLaunchMode` is a static enum case name).
- **CloudKit account transition** — `.public` for both old and new `AccountStatus` enum case names; never the user's iCloud user record id, container id, or any free-form Apple SDK error description (errors are not logged in this site).
- **UI destructive `persistentModelID`** — `.private`.
- **UI destructive action name** — `.public` (static literal like `"resetBudget"`).
- **Existing CloudKit `error.localizedDescription`** — `.public` (already in source). Apple framework error descriptions are reviewable in Console.app; they are not user input.

**Rationale.** Apple's `os.Logger` defaults non-literal interpolations to `.private`, but the default is silent and easy to bypass with a typo (`"\(value)"` vs `"\(value, privacy: .private)"`). Making the `privacy:` argument **explicit** at every call site makes review obvious and matches the `.swiftlint.yml` posture for explicit-over-implicit conventions in this repo.

### D6. Boundary contract — structural, not behavioral

**Decision.** The `diagnostic-logging` spec asserts: no helper exists in the `AnalyticsClient` API surface that takes a `Logger.*` value, an `OSLogEntry`, or any OSLog-derived input. Conversely, no code under `simple-recurring-budgets/` invokes `AnalyticsClient.track(...)` from inside a `Logger.*` call-site closure or as a deterministic side-effect of a `Logger` emission. This is enforced by code review (and reinforced by a structural Swift Testing assertion that no extension on `AnalyticsClient` accepts an OSLog-shaped input).

A single user action MAY produce one of each — e.g., a successful `Add Expense` (when F-8.02 ships) will fire `expense_logged` to Mixpanel **and** could later, if justified, write a `Logger.ui` entry; the two calls are independent.

**Alternatives considered.**

- *Runtime assertion that asserts no `Logger.*` callback ever calls `AnalyticsClient.track`.* Requires either an interceptor on `Logger` (impossible — `os.Logger` is a value type) or a global swizzle (over-engineering and breaks SwiftUI Previews). Structural assertion + code review is the proportionate guardrail for a single-developer codebase.
- *Defer the boundary contract to F-8.02.* No — F-8.01 ships first per F-8.01's own note. Establishing the spec now means F-8.02's planning artifact has an existing contract to point at, not a moving target.

**Rationale.** The boundary is a discipline, not a runtime behavior. Encoding it as a structural test (`AnalyticsClient` exposes no `Logger`-shaped API) catches the most common mis-implementation (a `track(loggerEntry:)` helper) while keeping CI fast and deterministic.

### D7. Test surface — Swift Testing, no `OSLogStore` reads

**Decision.** Add a single new test suite under `simple-recurring-budgetsTests/Logging/` (next to the existing `SpyAnalyticsClient.swift`):

- `AppLoggersTests` — asserts the three logger constants exist with the expected `subsystem` (Bundle identifier or fallback) and `category` strings. Covers the contract that the three categories listed in [`docs/tech-design-doc.md`](../../../docs/tech-design-doc.md) §7 match the source.
- `AnalyticsClientLoggerBoundaryTests` — asserts that `AnalyticsClient` (and its extension space inside the test target's import surface) exposes no method whose parameter type is `os.Logger`, `OSLogEntry`, `OSLogEntryLog`, or any other OSLog-shaped type. Implementation: a compile-time-style negative assertion using a `@Sendable` closure surface check on the concrete clients (`ConsoleAnalyticsClient`, `SpyAnalyticsClient`, and the existing `MixpanelAnalyticsClient` if present), backed by `#expect` against a known-good method count or a hand-curated allow-list of method signatures.

`OSLogStore` read-back is explicitly NOT added — see Non-Goals.

**Rationale.** Two small suites give us regression coverage for the two contracts most likely to drift: a future renamed category, and a future "convenience" route from `Logger` into `AnalyticsClient`. Both run in milliseconds and need no simulator configuration beyond the existing test plan.

### D8. Doc updates — fold into the same change

**Decision.** Tasks file lists the three doc updates inline (per `openspec/config.yaml` apply rules):

- `docs/tech-design-doc.md` §7 — add a one-paragraph line confirming the three categories match `AppLoggers.swift` and pointing at `docs/analytics-spec.md` §17 for the boundary; bump the revision history table.
- `docs/product-features-planning.md` F-8.01 — flip `**Status:**` from "Partially implemented" to "**Implemented.** Implemented by change `oslog-diagnostic-logging`."
- `docs/analytics-spec.md` §19 — update the "F-8.01 ships" row to a status reference (no content change to spec body).

**Rationale.** `openspec/config.yaml` and `AGENTS.md` both require docs updates to land in the same change when product / architecture content materially moves. Flipping a feature status counts.

## Risks / Trade-offs

- **[Risk] Future contributor adds a `Logger.ui` call site without explicit `privacy:` for an interpolated value.** → **Mitigation.** The `diagnostic-logging` spec encodes the explicit-`privacy:` rule with a normative SHALL. PR review enforces it. SwiftLint does not currently have a rule for this and we do not add one (over-engineering for a single-developer codebase).
- **[Risk] Bootstrap log line emits before `Logger` is fully resolved (e.g., bundle identifier missing).** → **Mitigation.** `AppLoggers.swift` already falls back to `"simple-recurring-budgets"` when `Bundle.main.bundleIdentifier` is nil; the line is safe to emit in `init()`.
- **[Risk] CloudKit account transition log races against `loadICloudStatus()` reentry on rapid notification storms.** → **Mitigation.** `loadICloudStatus()` runs on the main actor; transitions are sequential. The `old != new` guard is a single comparison; no shared mutable state beyond the `@Bindable` `accountStatus` already in use.
- **[Trade-off] No runtime assertion on log line emission.** A buggy refactor could remove a `Logger.ui.debug(...)` call site silently. **Accepted.** The cost of an `OSLogStore`-driven test (CI flakes, simulator coupling) outweighs the value at this scale; spec + code review is sufficient.
- **[Trade-off] `persistentModelID` interpolated as `.private` is opaque to log readers without a paired Console.app "Include Info Messages" + device-attached debug profile.** **Accepted.** F-8.01's intent is debugging, not telemetry; developers attaching to a device for a live debug session can flip privacy redaction off, and the alternative (`.public` IDs) leaks identifiers into the system log archive.

## Doc alignment

- [`docs/main-prd.md`](../../../docs/main-prd.md) §6.3 — aligned. No update needed.
- [`docs/product-features-planning.md`](../../../docs/product-features-planning.md) F-8.01 — status flips to **Implemented** (task in `tasks.md`).
- [`docs/tech-design-doc.md`](../../../docs/tech-design-doc.md) §7 — confirmation paragraph added (task in `tasks.md`); per `docs/analytics-spec.md` §19.
- [`docs/analytics-spec.md`](../../../docs/analytics-spec.md) §19 — "F-8.01 ships" row marked done (task in `tasks.md`).

No conflicts.
