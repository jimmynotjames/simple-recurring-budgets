# Budget calculations rewrite — algorithm design


| Field            | Value                                                                  |
| ---------------- | ---------------------------------------------------------------------- |
| **Version**      | 1.1                                                                    |
| **Last Updated** | 2026-06-11                                                             |
| **Author**       | Jimmy Ho                                                               |
| **Status**       | **HISTORICAL — shipped.** The rewrite is fully implemented (`Domain/BudgetCalculator.swift` and friends) and synced to the openspec specs. The current authoritative spec is `openspec/specs/budget-math/spec.md`; read this doc for design rationale only, not as pending work. |
| **Inputs**       | [budget-calculations-rewrite-reqs.md](budget-calculations-rewrite-reqs.md) |


> **HISTORICAL.** This document was the implementation design for the rewrite briefing in
> [budget-calculations-rewrite-reqs.md](budget-calculations-rewrite-reqs.md). The change has
> shipped; where this doc and the code or `openspec/specs/budget-math/spec.md` disagree (e.g.
> the lifecycle enum shipped as `BudgetLifecycleState`, not `LifecycleState`), the code and spec
> win. Section numbers `§X.Y` without further qualification refer to **that** briefing;
> internal cross-references use `§A.X` (this doc).
>
> Scope: **core period/budget math only.** UI surfaces (chips, lifecycle presentations, date
> picker bounds, toolbar actions) are mentioned only as inputs to or outputs of the algorithm.
> Detailed UI wiring is a separate planning step.

---

## Glossary

Terms used throughout this doc. For broader product terms, see `[main-prd.md` §10.1](main-prd.md#101-glossary).

> [!NOTE]
> **The definitions below are informative, not normative.** They are short-form summaries meant
> to orient a reader, not to specify behavior. If a definition here disagrees with a detailed
> description elsewhere in this doc (e.g. the algorithm steps in §A.4, helper contracts in §A.5,
> or write-site rules in §A.6) or with the actual shipped code, **the detailed description / the
> code wins.** Edge cases and special handling are deliberately omitted here for brevity; consult
> the linked sections for the precise rules.


| Term                                            | Meaning                                                                                                                                                                                                                                                                                                                                                                                                                             |
| ----------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Chip**                                        | Shorthand for the budget's status displays on the Budgets list row and Budget detail header — the **Remaining** number and the **Carry-over** number (plus any lifecycle overlay like "Starts on X" / "Paused since X" / "Ended on X"). Implemented as the `CarryOverChip` view + the header's Remaining label. When the doc says "the chip updates mid-period," it means *whichever of those surfaces is showing* for that budget. |
| **Remaining**                                   | `allocation − sum(expenses in the current period)`. Per-period "left to spend." Not adjusted by Carry-over for display. For Specific Dates: `allocation − sum(expenses in the window)`.                                                                                                                                                                                                                                             |
| **Carry-over**                                  | Signed cumulative surplus/deficit. Two components: (1) `walkerSum` — net across all *completed active prior periods* (§A.5.3); (2) `currentPeriodSpillover` — the *committed* overflow from the current period, folded in live (§A.5.6 asymmetric rule). Recurring budgets only; `nil` for Specific Dates.                                                                                                                          |
| **Spillover** (`currentPeriodSpillover`)        | The *committed* portion of the current period's net that has spilled out of `[0, effectiveAllocation]` — overspend (`remaining < 0`) or add-funds excess (`remaining > effectiveAllocation`). 0 when `remaining` is inside the ordinary range. Added to `walkerSum` to produce Carry-over (§A.5.6).                                                                                                                                 |
| **Period / Budget Period**                      | One repeat of a recurring budget — a day (daily), a week (weekly), 14 days (biweekly), or a calendar month (monthly). Specific Dates budgets have **no repeating periods**; their entire lifetime is a single closed **window** `[startDate, endDate]` (the body uses "window" throughout for this case, per briefing §5.3).                                                                                                        |
| **Walker**                                      | The carry-over computation in §A.5.3 that iterates completed prior periods and folds each *active* one's `(allocation − expenses)` into the running carry-over. Paused periods are skipped (contribute 0) per the §A.5.4 classification.                                                                                                                                                                                            |
| **Snapshot**                                    | The `BudgetSnapshot` value returned by `BudgetCalculator.snapshot(...)` — a pure, read-time computation. The algorithm has no other public entry point.                                                                                                                                                                                                                                                                             |
| **Lifecycle state**                             | One of `.preStart`, `.active`, `.paused`, `.postEnd`. Carried on `BudgetSnapshot` and drives the UI's overlay treatment.                                                                                                                                                                                                                                                                                                            |
| **Active / paused period**                      | A *period* (not a moment) is "active" if math accrues to it, "paused" otherwise. Classification rules in §A.5.4. Pause/Resume operates at period granularity, never mid-period.                                                                                                                                                                                                                                                     |
| **Pause-action period / Resume-action period**  | The period containing a Pause or Resume `LifecycleEvent`. Both are **active** in full (no proration). Briefing §5.5.                                                                                                                                                                                                                                                                                                                |
| **Effective start date** (`effectiveStartDate`) | The algorithm's resolved start instant for a budget — normalized for safety and consistency. Precise definition (including the safety-net fallback for nil `startDate` and the start-of-day normalization) lives in §A.4.0.                                                                                                                                                                                                         |
| **Effective now** (`effectiveNow`)              | Clock time used by the algorithm, clamped so the chip freezes once the budget ends. Precise definition in §A.4.1 step 4 + §A.4.0.                                                                                                                                                                                                                                                                                                   |
| `**effectiveFrom`**                             | The period-boundary key on an `AllocationChange` row. An allocation edit's value applies starting at the period whose start equals this date.                                                                                                                                                                                                                                                                                       |
| **Backdated expense**                           | An `ExpenseItem` whose `date` is earlier than `now` — possibly inside a prior completed period, possibly inside a paused stretch.                                                                                                                                                                                                                                                                                                   |
| **Greenfield**                                  | The app has no production users. The data model can change freely; no migrations are required (briefing §1).                                                                                                                                                                                                                                                                                                                        |


---

## A.1. Goals and non-goals

**User actions / expectations this section addresses:**

- Adding, editing, or deleting an expense and seeing the chip update immediately (no waiting for a period boundary).
- Editing today's allocation without retroactively rewriting prior periods' contributions.
- Adding a back-dated expense — including into a prior active period of a budget that is currently paused.
- Pausing/Resuming at any moment within a period, without worrying about proration.
- Creating one-shot "trip" budgets with a single fixed window (Specific Dates).
- Setting a per-budget Start Date and (optional) End Date independent of the global week-start.
- Asking Siri "how much is left?" and getting the same number the chip shows.

### A.1.1. Goals

1. The chip values update **mid-period** — there is no stored carry-over to go stale (§2.1).
  The Remaining chip is fully live; the Carry-over chip is **asymmetrically live** — it absorbs
   the current period's *committed* overflow (overspend or add-funds excess) in real time, while
   ordinary mid-period slack is held until the period closes (§A.5.6).
2. Allocation edits never retroactively rewrite the carry-over contribution of prior completed
  periods (§2.1, §5.1).
3. Backdated expenses — including into prior active periods of a currently-paused budget —
  propagate correctly through the carry-over (§2.7, briefing §6.7 item 5).
4. Pause/Resume operates at period granularity with no proration; the within-period timing of
  the action is irrelevant to math (§2.7, §5.5).
5. Specific Dates is a first-class period type with its own one-window semantics (§2.5, §5.3).
6. `startDate` and `endDate` are first-class fields; pre-start, post-end, and paused states have
  distinct lifecycle classifications surfaced to the UI (§2.2, §2.9).
7. The single value returned by the algorithm must equal the value the chip displays everywhere,
  including the Voice query feature F-7.03 (§2.1).
8. Reset Cadences is removed entirely. There is no scheduled-reset code path (§2.6, §5.4).

### A.1.2. Non-goals

- **Migrations.** Greenfield app; rewrite the model and wipe the simulator (briefing §1).
- **Timer-driven refresh** for clock-driven period crossings while the app is open. Refresh is
driven by user actions and `scenePhase == .active` (§2.1, F-2.01).
- **Currency conversion.** Allocation edits and currency changes are independent — the rewrite
does not touch F-3.04's label-only currency semantics.
- **UI changes.** The Add/Edit screens, chips, toolbars, and date-picker constraints are
consumers of this design but not specified here.

---

## A.2. Data model changes

**User actions / expectations this section addresses:**

- Saving a budget with a Start Date and (optional) End Date.
- Preserving historical allocations so prior-period math is never rewritten by a future edit.
- Pausing/Resuming a budget any number of times — including before `startDate` — and having
those events sync across devices.
- Resetting Carry-Over without losing allocation history or pause/resume history.
- Deleting a budget and having its history cleaned up automatically.

The rewrite reshapes the `Budget` entity. `ExpenseItem` is unchanged.

> [!IMPORTANT]
> **CloudKit relationship-optionality pattern (applies to every new relationship below).**
> Per `[docs/tech-design-doc.md` §3.1 and §4.3](tech-design-doc.md#31-approach), every SwiftData
> relationship that syncs through CloudKit MUST be stored as an **optional collection** on the
> parent side, with a non-optional computed accessor for all app code. The precedent is the
> existing `Budget.expenses: [ExpenseItem]?` (stored, do not access outside the model definition)
> paired with `expenseItems: [ExpenseItem] { get { expenses ?? [] } }` (the canonical accessor).
>
> For this rewrite, that means:
>
> ```swift
> // STORED (optional, CloudKit-friendly) — do not access outside the model definition
> @Relationship(deleteRule: .cascade, inverse: \AllocationChange.budget)
> var allocationChangesStorage: [AllocationChange]?
>
> @Relationship(deleteRule: .cascade, inverse: \LifecycleEvent.budget)
> var lifecycleEventsStorage: [LifecycleEvent]?
>
> // CANONICAL ACCESSORS (non-optional, used everywhere in app code)
> var allocationChanges: [AllocationChange] {
>   get { allocationChangesStorage ?? [] }
>   set { allocationChangesStorage = newValue }
> }
> var lifecycleEvents: [LifecycleEvent] {
>   get { lifecycleEventsStorage ?? [] }
>   set { lifecycleEventsStorage = newValue }
> }
> ```
>
> The exact property names are implementer's choice (e.g. `expenses` / `expenseItems` uses a
> shorter raw name; you may prefer that). The non-negotiable rules are: **(a) the stored property
> is `Optional`**, **(b) a non-optional computed accessor exists**, **(c) no call site outside
> the `@Model` definition touches the raw optional property**. Skipping this pattern compiles and
> runs locally but breaks under CloudKit out-of-order sync.

### A.2.1. `Budget` entity — final shape


| Field                   | Type                                        | Notes                                                                                                                                                                                                                                                                                                              |
| ----------------------- | ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `id`                    | `UUID`                                      | Unchanged.                                                                                                                                                                                                                                                                                                         |
| `name`                  | `String`                                    | Unchanged.                                                                                                                                                                                                                                                                                                         |
| `currencyCode`          | `String` (ISO 4217)                         | Unchanged.                                                                                                                                                                                                                                                                                                         |
| `period`                | `String` (raw `BudgetPeriod`)               | Now includes `.specificDates` (§A.3).                                                                                                                                                                                                                                                                              |
| `sortOrder`             | `Int`                                       | Unchanged.                                                                                                                                                                                                                                                                                                         |
| `createdAt`             | `Date`                                      | Unchanged. Used as the safety-net fallback if `startDate` is nil at read time (§2.4, briefing).                                                                                                                                                                                                                    |
| `lastModified`          | `Date`                                      | Unchanged. Bumped on user-initiated edits only; never written by the read path.                                                                                                                                                                                                                                    |
| `isCarryOverEnabled`    | `Bool`                                      | Unchanged. Display-only flag for recurring types. Algorithm ignores it for `.specificDates` (§2.5).                                                                                                                                                                                                                |
| `**startDate`**         | `Date?` **(new)**                           | Semantically required by the UI; stored optional for CloudKit (§2.2). UI saves as start-of-day in the user's calendar; algorithm normalizes defensively (§A.4.0). Falls back to `createdAt` if nil.                                                                                                                |
| `**endDate`**           | `Date?` **(new)**                           | Genuinely optional for recurring; required by the UI for `.specificDates` (§2.2). UI saves as start-of-day of the **last included day**; the algorithm internally uses `effectiveEndExclusive = startOfDay(endDate + 1 day)` so the user-picked "ends on May 15" means "active through all of May 15." See §A.4.0. |
| `**lastResetDate`**     | `Date?` **(renamed)**                       | Replaces `carryOverLastResetDate`. `nil` = no manual reset has occurred. Walker floor (§A.5.3).                                                                                                                                                                                                                    |
| `**allocationChanges`** | one-to-many to `AllocationChange` **(new)** | Ordered history of allocation values. At least one entry on a saved budget — the initial allocation (§A.2.2). Stored as `allocationChangesStorage: [AllocationChange]?` per the CloudKit pattern above; this row names the canonical accessor.                                                                     |
| `**lifecycleEvents`**   | one-to-many to `LifecycleEvent` **(new)**   | Ordered history of pause/resume actions. Empty for a never-paused budget (§A.2.3). Stored as `lifecycleEventsStorage: [LifecycleEvent]?` per the CloudKit pattern above; this row names the canonical accessor.                                                                                                    |


**Removed from `Budget`** (briefing §2.2, §2.6):

- `allocation: Decimal` — superseded by `allocationChanges`.
- `carryOverAmount: Decimal` — no longer stored; computed live.
- `carryOverLastProcessedDate: Date` — no longer needed; the walker is live.
- `resetCadence: String` — feature deleted outright.

### A.2.2. `AllocationChange` (new `@Model`)

```swift
@Model final class AllocationChange {
  var id: UUID = UUID()
  /// The natural period-boundary date at which this allocation becomes effective.
  /// For recurring budgets (daily/weekly/biweekly/monthly), this is always a natural period
  /// start: for daily/weekly/biweekly that equals `effectiveStartDate` (the cycle anchors on
  /// it); for monthly that equals the start of the calendar month containing
  /// `effectiveStartDate` (= `effectiveStartDate` itself when `startDate` is on the first of
  /// a month; = an earlier date when `startDate` is mid-month). For subsequent entries,
  /// equal to the `currentPeriodStart` at the time the edit was committed (also always a
  /// natural period boundary). For Specific Dates budgets, `effectiveFrom = effectiveStartDate`
  /// — there are no period boundaries to align to. Aligning to the natural boundary is what
  /// makes the "mutate vs. insert" check in §A.5.2 correctly recognize a same-period edit on a
  /// monthly budget with a mid-month `startDate`.
  var effectiveFrom: Date = Date()
  var amount: Decimal = 0
  /// User-action timestamp for the *row*, set on insert and bumped on every mutate. Used as the
  /// **tiebreak** when two rows share the same `effectiveFrom` (the rare cross-device case where
  /// each device inserted its own row before sync). Distinct from `effectiveFrom`, which is the
  /// period boundary the allocation applies to; this field reflects "when did this row get
  /// written." Latest `lastModified` wins.
  var lastModified: Date = Date()
  @Relationship(deleteRule: .nullify) var budget: Budget?
  init(effectiveFrom: Date, amount: Decimal) { ... }
}
```

**Storage rules:**

- A saved `Budget` always has **at least one** `AllocationChange`. The first one — created in
the same transaction as the budget itself — has `amount == initialAllocation` and an
`effectiveFrom` aligned to a natural period boundary:
  - **Daily / weekly / biweekly:** `effectiveFrom == effectiveStartDate` (the cycle anchors on
  `effectiveStartDate`, so its start-of-day-normalized value *is* the natural boundary).
  - **Monthly:** `effectiveFrom == start of the calendar month containing effectiveStartDate`.
  If the user picked a mid-month `startDate` (e.g. April 15), the initial entry is stored at
  April 1, **not** April 15. The row's `effectiveFrom` may therefore precede the budget's
  `startDate`; this is correct and required for correctness — see the note below.
  - **Specific Dates:** `effectiveFrom == effectiveStartDate`. There are no period boundaries
  to align to; the single entry represents the allocation for the entire window.
- **Why monthly mid-month uses the month boundary, not `startDate`.** When a user creates a
monthly budget with `startDate = April 15` and later edits the allocation on, say, April 20,
§A.5.2's "Latest-wins within a period" rule stores the edit at `currentPeriodStart = April 1`
(the natural month boundary). If the *initial* entry were stored at `April 15` (a mid-period
date), the history would now contain two entries for the same period at two different
`effectiveFrom` values, and `allocationInEffect`'s sort-and-pick-latest logic would select the
April 15 entry (by `effectiveFrom`), silently swallowing the user's edit. Aligning the initial
entry to the natural boundary makes the "mutate-or-insert" check in §A.5.2 match the existing
row and update it in place.
- Adding a new entry uses the same period-boundary key (`effectiveFrom`) as the period in progress
at the time of the edit. If an entry already exists with the same `effectiveFrom`, **mutate it**
(update both `amount` and `lastModified`) rather than appending — this implements the
"latest-wins within the same period" rule (briefing §6.2 item 3).
- **Concurrent edits across devices — deterministic tiebreak.** The "mutate, not append" invariant
holds *per device write only*. If two devices both edit allocation in the same period before
sync, each creates its own row at the same `effectiveFrom` because neither sees the other's
record yet. After sync, both rows persist. The algorithm sorts by `(effectiveFrom, lastModified)`
and picks the entry with the latest `effectiveFrom <= date`; for ties on `effectiveFrom`, the
one with the later `lastModified` wins. This is "last-writer-wins by wall-clock at the row
level" — the same model CloudKit uses for field-level merges, and the same model the user
intuits from any other multi-device app.
- Entries are conceptually ordered by `effectiveFrom`, with `lastModified` as the secondary key.
Sort at read time; no sort-order column.

### A.2.3. `LifecycleEvent` (new `@Model`)

```swift
@Model final class LifecycleEvent {
  var id: UUID = UUID()
  /// Stored as `LifecycleEventKind.rawValue`. Read/write via the `kind` accessor.
  /// Storing the raw string (rather than the enum directly) keeps this column visible
  /// to `#Predicate<LifecycleEvent>` filters — Codable-backed enum storage is opaque to
  /// predicates. Same convention as `Budget.period`.
  var kindRawValue: String = LifecycleEventKind.pause.rawValue
  /// The user-action timestamp. See "pre-start pause" handling below for the one case
  /// where this is a synthetic value rather than wall-clock-now.
  var date: Date = Date()
  @Relationship(deleteRule: .nullify) var budget: Budget?

  var kind: LifecycleEventKind {
    get { LifecycleEventKind(rawValue: kindRawValue) ?? .pause }
    set { kindRawValue = newValue.rawValue }
  }
  init(kind: LifecycleEventKind, date: Date) { ... }
}

enum LifecycleEventKind: String, Codable { case pause, resume }
```

Note the deliberate absence of `lastModified`. `LifecycleEvent` rows are **append-only** — they are never mutated after insert (§A.5.2's mutate-or-insert pattern applies only to `AllocationChange`). For append-only rows the conceptual `lastModified` would always equal the value `date` already carries on the normal-pause / normal-resume path. The only cases where they would differ are pre-start pauses across devices that all store the same synthetic `date = effectiveStartDate − ε`, and in that race **all the rows are equivalent** (same `kind`, identical effect on `isActive` classification), so a tiebreak field would be ceremony with no semantic gain. Sort by `date` alone.

**Storage rules:**

- Empty for a never-paused budget. Append-only by user action.
- Sort at read time by `date` ascending. CloudKit-late arrivals re-sort naturally on next read.
- **Pre-start pause carve-out.** If the user invokes Pause while `now < effectiveStartDate`, the
event is stored with `date == effectiveStartDate - 1.nanosecond` (or equivalent ε before
`effectiveStartDate`). Note this uses `**effectiveStartDate`**, not the raw `Budget.startDate`
— they are the same in the normal case (UI saves `startDate` as start-of-day), but using
`effectiveStartDate` keeps the carve-out correct in the malformed-sync-record fallback case
too. This places the event logically *before* the first period rather than *in* it, so the
algorithm's "any event in this period → period is active" rule does not apply and the first
period correctly starts paused (§5.5 "Pause while `startDate` is in the future"). The
user-facing label can render the pause as "Paused on `startDate`" — only the stored timestamp
is offset.
- **Concurrent pause/resume across devices.** Both events are persisted and sorted by `date`
ascending on read. For per-period classification (Rule 1 / Rule 2 of §A.5.4) the algorithm
processes them in chronological order; events with the same `date` are equivalence-class
duplicates (the only realistic same-`date` collision is two pre-start pauses across devices,
all of which store `date == effectiveStartDate − ε` and produce identical classification).
No "phantom paused period" is possible because the classification only depends on which
events fall inside the period and which is the latest event strictly before it. Live
post-`startDate` actions from independent devices produce naturally distinct `date` values
(wall-clock-now never collides to the nanosecond across devices in practice).

### A.2.4. Cascade rules

- `Budget → ExpenseItem`: cascade delete (unchanged).
- `Budget → AllocationChange`: cascade delete (new). Deleting the budget removes its history.
- `Budget → LifecycleEvent`: cascade delete (new). Same.

Manual **Reset Budget** continues to delete all `ExpenseItem`s but does **not** delete
`AllocationChange`s or `LifecycleEvent`s; see §A.6.4 for what it does do.

### A.2.5. `BudgetPeriod` enum

```swift
enum BudgetPeriod: String, Codable, CaseIterable {
  case daily, weekly, biweekly, monthly
  case specificDates  // NEW
}
```

- `Comparable` conformance is retained for the recurring four. `.specificDates` is intentionally
*not* comparable to the recurring cases — call sites that depend on the ordering should switch
exhaustively rather than use `<`.
- `defaultResetCadence` (the `BudgetPeriod` extension) is **deleted** along with the
`ResetCadence` enum and `Budget.resetCadence` column (§2.6).

### A.2.6. `SchemaV1.swift` / `BudgetMigrationPlan.swift`

Per briefing §1: greenfield, no migrations. **Update, do not delete** these two files to reflect
the new shape — they remain as the lone schema definition. Do not introduce `SchemaV2` or any
`VersionedSchema` ceremony. `SchemaV1.models` gains the two new `@Model` types
(`AllocationChange`, `LifecycleEvent`) alongside the existing `Budget` and `ExpenseItem`.

### A.2.7. `ExpenseItem` — unchanged

Included here for completeness. **No changes** are required by this rewrite. The current shape
in `[simple-recurring-budgets/Models/ExpenseItem.swift](../simple-recurring-budgets/Models/ExpenseItem.swift)`
is reproduced verbatim:

```swift
@Model final class ExpenseItem {
  var id: UUID = UUID()
  /// Signed: positive = expense, negative = add funds (F-6.01).
  var amount: Decimal = 0
  var name: String?
  var date: Date = Date()
  var createdAt: Date = Date()
  var lastModified: Date = Date()
  /// e.g. "Cash", "Credit Card" (F-6.02). Stored for future use.
  var expenseType: String?

  var budget: Budget?

  var isAddFunds: Bool { amount < 0 }
  var displayAmount: Decimal { amount < 0 ? -amount : amount }

  init(amount: Decimal = 0, name: String? = nil, date: Date = Date(), expenseType: String? = nil) { ... }
}
```

Notes:

- The algorithm reads only `amount` and `date`. `name`, `createdAt`, `lastModified`,
`expenseType`, and the relationship back to `Budget` are untouched.
- The signed-amount convention (negative = add funds, F-6.01) is preserved as-is. The walker
(§A.5.3) and the current-period sum (§A.4.1 step 9) treat negative amounts uniformly — they
flow through the `reduce` and naturally increase `remaining` / `carryOver`.
- Per the §A.6 project-wide rule, any user-initiated edit to an `ExpenseItem` continues to bump
its own `lastModified` (and the parent `Budget.lastModified` is bumped at the call site that
triggers the chip refresh).

---

## A.3. Result types

**User actions / expectations this section addresses:**

- Reading the chip values on the Budgets list and Budget detail screens.
- Voice query (F-7.03) returning exactly the `remaining` and `carryOver` the chip is showing.
- The UI rendering pre-start, active, paused, and post-end states with distinct presentations.

The algorithm has a single entry point that returns a value object — a pure snapshot computed
from the budget's current state.

```swift
struct BudgetSnapshot: Equatable, Sendable {
  /// Lifecycle classification at `now`. Drives chip presentation in the UI.
  let lifecycleState: LifecycleState

  /// Allocation in effect for the period containing `effectiveNow`.
  /// For `.specificDates`, this is the latest-wins allocation.
  let effectiveAllocation: Decimal

  /// Remaining for the current Budget Period (recurring) OR for the window (`.specificDates`).
  /// — Recurring: `effectiveAllocation − expenses dated in [effectivePeriodStart, effectivePeriodEnd)`.
  /// — Specific Dates: `effectiveAllocation − expenses dated in [effectiveStartDate, effectiveEndExclusive)`,
  ///   which covers every calendar day from `startDate` through `endDate` inclusive (§A.4.0).
  /// — Pre-start / paused: 0 (UI hides the Remaining chip and renders a state label instead).
  let remaining: Decimal

  /// Signed cumulative carry-over. Two components:
  ///   • `walkerSum`: net `(allocation − expenses)` over completed *active* prior periods (§A.5.3).
  ///   • `currentPeriodSpillover`: the *committed* portion of the current period's net — i.e.,
  ///     only the part that has spilled out of `[0, effectiveAllocation]` — folded in live.
  ///     This is the "asymmetric live coupling" rule (§A.5.6): overspend and add-funds excess
  ///     show up in carry-over immediately, but ordinary mid-day slack does not.
  /// `carryOver = walkerSum + currentPeriodSpillover`.
  /// `nil` for `.specificDates` (no recurring periods → no separate carry-over chip).
  /// Frozen behavior in `.postEnd` and `.paused` states is intrinsic — see §A.5.
  let carryOver: Decimal?

  /// Start of the period containing `effectiveNow` (clamped to `effectiveStartDate` if narrower).
  /// For `.specificDates`, this is `effectiveStartDate`. Always start-of-day-aligned per §A.4.0.
  let effectivePeriodStart: Date

  /// Exclusive end of the period containing `effectiveNow` (clamped to `effectiveEndExclusive`
  /// if narrower). For `.specificDates`, this is `effectiveEndExclusive` (the start of the day
  /// after `endDate`). Always start-of-day-aligned per §A.4.0.
  let effectivePeriodEnd: Date
}

enum LifecycleState: Equatable, Sendable {
  case preStart       // now < effectiveStartDate
  case active         // now in [effectiveStartDate, effectiveEndExclusive) AND current period is not paused
  case paused         // current period falls inside a paused stretch
  case postEnd        // now >= effectiveEndExclusive (i.e. the day after endDate has begun)
}
```

Notes:

- `LifecycleState.postEnd` takes precedence over `.paused` when both would apply (briefing §6.7
item 12: "if `endDate` falls inside a paused period, no special handling is required — the
chip is already frozen ... and `endDate` simply makes that frozen state terminal").
- The Voice query (F-7.03) returns the same `remaining` and `carryOver` the chip would show, so
the snapshot is the single source of truth (§2.1).

---

## A.4. Main algorithm: `BudgetCalculator.snapshot(...)`

**User actions / expectations this section addresses:**

- Every chip read in the app: view appearance (`.task`), `scenePhase == .active`, and after any
write that could affect the value (expense add/edit/delete, allocation edit, start/end-date
edit, pause/resume, reset).
- Voice query reading the same numbers.

```swift
enum BudgetCalculator {
  static func snapshot(
    budget: Budget,
    expenses: [ExpenseItem],   // typically `budget.expenseItems`; passed in for testability
    now: Date,
    calendar: Calendar
  ) -> BudgetSnapshot
}
```

The signature is **pure**: no `ModelContext`, no fetches, no side effects. `ExpenseItem` is read
for `.amount` and `.date` only.

### A.4.0. Date normalization (`startDate` / `endDate`)

`Budget.startDate` and `Budget.endDate` are calendar days picked by the user in the Add/Edit
Budget UI. Internally the algorithm normalizes them so the user's intuitive mental model —
"`endDate = May 15` means the budget is active for all of May 15, and becomes Ended on May 16" —
holds, and so the recurring half-open windows and the Specific Dates window use the same
inclusivity rules.

The three derived values, computed once at the top of `snapshot(...)` and used everywhere
downstream:

```swift
let effectiveStartDate: Date = calendar.startOfDay(
  for: budget.startDate ?? budget.createdAt
)

let effectiveEndInclusive: Date? = budget.endDate.map { calendar.startOfDay(for: $0) }

let effectiveEndExclusive: Date = effectiveEndInclusive.map { inclusive in
  calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: inclusive)!)
} ?? .distantFuture
```

Semantics:

- `**effectiveStartDate**` is the inclusive lower bound. An expense whose `date >= effectiveStartDate`
(the first instant of the start day) is in range; anything earlier is out. The `startOfDay` call
is **defensive** — the UI saves `startDate` as start-of-day already, but normalizing on read
protects against malformed sync records.
- `**effectiveEndInclusive`** is the start-of-day of the last active day. Used to **clamp
`effectiveNow`** in step 4: when `now` is past the end of the budget, we still want the
algorithm to operate as if `now` were on the final active day, so the final period is the
one the algorithm calls "current." Optional; absent when `endDate` is nil.
- `**effectiveEndExclusive**` is the start-of-day **after** `endDate` — i.e., midnight at the
beginning of "the day the budget is no longer active." It is the **exclusive upper bound** for
every expense window in this algorithm. A budget ending on `May 15` has
`effectiveEndExclusive = May 16 00:00`, so an expense dated `May 15 23:59` is in
`[startDate, May 16)` — included. The chip becomes `.postEnd` the moment
`now >= effectiveEndExclusive`.
- For a budget with no `endDate` (recurring, optional), `effectiveEndInclusive = nil` and
`effectiveEndExclusive = .distantFuture`, so both clamps are no-ops.

Throughout this doc, when a step uses `endDate` for expense filtering, read it as
"`effectiveEndExclusive`." When a step clamps `now`, read it as "`effectiveEndInclusive`." When
a step uses `startDate`, read it as "`effectiveStartDate`." The same convention applies in the
Specific Dates branch (§A.4.2) — the historical `[startDate, endDate]` closed window becomes
`[effectiveStartDate, effectiveEndExclusive)`, which is identical in coverage (every calendar
day from start through end inclusive) but consistent with the recurring window's half-open form.

### A.4.1. Steps

The function performs the following in order. Each step references the helpers in §A.5.

1. **Resolve and normalize the date bounds.** Compute `effectiveStartDate` and
  `effectiveEndExclusive` per §A.4.0. Both are start-of-day-aligned. The `?? createdAt` branch in
   `effectiveStartDate` is the safety net for malformed sync records (§2.4); the UI guarantees
   `startDate` is set on save.
2. **Pre-start short-circuit.** If `now < effectiveStartDate`:
  - Return `BudgetSnapshot(state: .preStart, remaining: 0, carryOver: 0 or nil)`.
  - `carryOver = nil` for `.specificDates`; `0` for recurring.
  - `effectiveAllocation = allocationInEffect(at: effectiveStartDate, history: allocationChanges)`
  — i.e. the user-configured initial allocation. `remaining` is still `0` (no period is yet
  in progress), but `effectiveAllocation` reflects what each period *will* allocate once
  `startDate` is reached. The UI may use this to render copy like "$100/mo, starts on May 20".
  The exact value surfaced pre-start is intentionally non-zero so the user can see what they
  configured; the chip's "Remaining" number is still `0` until `startDate`.
  - `effectivePeriodStart = effectivePeriodEnd = effectiveStartDate` (sentinel for the UI).
3. **Branch on period type.**
  - If `period == .specificDates`: jump to §A.4.2 (specific-dates branch).
  - Else: continue to step 4 (recurring branch).
4. **Clamp `now` to the last active day.** `effectiveNow = min(now, effectiveEndInclusive ?? .distantFuture)`.
  From this point onward, period-boundary computations use `effectiveNow`. The clamp uses
   `effectiveEndInclusive` (the start of the last active day) **not** `effectiveEndExclusive`
   (the start of the day after) so that, once the budget has ended, the algorithm still
   identifies the *final active day's* period as "current" — `periodStart(containing:  effectiveNow)` lands inside the final period rather than past it. (Note: while clamping is
   active, `effectiveNow` may strip time-of-day from `now`. That has no effect on period
   detection — `periodStart` is start-of-day-aligned for every recurring period type — and is
   correct.)
5. **Resolve period anchors** (#240, change `weekly-global-week-start`):
  - `weekStart` is the **caller-provided global week grid** — production callers pass
  `AppSettings.weekStartDay` into `snapshot(budget:expenses:now:calendar:weekStart:)` (the
  parameter has no default). It is consumed only by the `.weekly` branch of
  `PeriodCalculator`; every weekly budget shares this grid, like every monthly budget
  shares the calendar-month grid. A weekly `startDate` off the grid clips the first
  period via `effectivePeriodStart = max(...)` in step 6 (full allocation, no proration).
  - `biweeklyAnchor = effectiveStartDate` — the 14-day cycle's phase comes from the
  budget's own start date and is never affected by `weekStart`.
6. **Compute the current period.** `currentPeriodStart = PeriodCalculator.periodStart(containing:
  effectiveNow, ...)`;` currentPeriodEnd = PeriodCalculator.periodEnd(containing: effectiveNow,
   ...)`. Then:
  - `effectivePeriodStart = max(currentPeriodStart, effectiveStartDate)`.
  - `effectivePeriodEnd = min(currentPeriodEnd, effectiveEndExclusive)`.
7. **Classify the current period** (§A.5.4). `isCurrentPaused = !isActive(periodStart:
  effectivePeriodStart, periodEnd: currentPeriodEnd, events: lifecycleEvents)`. Note: pass`  effectivePeriodStart`(i.e.`max(currentPeriodStart, effectiveStartDate)`), **not`**  currentPeriodStart`. This ensures a pre-start pause event stored at` startDate − ε`is  correctly classified as "before the first period" even when`startDate`falls mid-period  (e.g. a monthly budget with`startDate = April 15` — see §A.5.4 "Pre-start pause").
8. **Look up the current allocation** (§A.5.2). `effectiveAllocation = allocationInEffect(at:
  max(currentPeriodStart, effectiveStartDate), history: allocationChanges)`. The `max(...)`
  clamp is **load-bearing** for first periods that start mid-grid: the initial
  `AllocationChange.effectiveFrom` is written at `effectiveStartDate` (§A.6.1), which for a
  monthly budget created mid-month — or, since #240, a weekly budget whose `startDate` is off
  the global `weekStart` grid — sits *inside* the first grid period. Querying at
  `effectiveStartDate` lands on that row directly; querying at `currentPeriodStart` alone
  would fall through to the earliest-row fallback (same amount today, but the direct hit is
  what the §A.6.2 governing-row edit key relies on for live/walker agreement). For
  grid-aligned budgets the clamp is a no-op.
9. **Compute `remaining` for the current period.**
  - If `isCurrentPaused`: `remaining = 0`. The UI hides the Remaining chip and renders
   "Paused since X" instead — see §A.5.5.
  - Else: `currentPeriodExpenses = sum of e.amount for e in expenses where effectivePeriodStart <= e.date < effectivePeriodEnd`. `remaining = effectiveAllocation − currentPeriodExpenses`. (Negative results are valid — overspending.)
10. **Walk completed prior periods to compute `walkerSum`** (§A.5.3).
11. **Determine `lifecycleState`** in this priority order:
  1. `if budget.endDate != nil && now >= effectiveEndExclusive` → `.postEnd`. If `endDate` is
    `nil`, `effectiveEndExclusive = .distantFuture` and this priority never fires. Note `>=`
     (not `>`): the moment `now` reaches the start of the day after `endDate`, the budget is
     Ended — consistent with §A.4.0's "active through all of `endDate`" semantics.
  2. `isCurrentPaused` → `.paused`
  3. Else → `.active`
12. **Compute `currentPeriodSpillover`** per the asymmetric coupling rule (§A.5.6). The rule
  depends on `lifecycleState`:
  - `.active`: spillover absorbs only the *committed* overflow in either direction:
    ```
    if remaining < 0:                            spillover = remaining            // overspend
    else if remaining > effectiveAllocation:     spillover = remaining - effectiveAllocation  // add-funds excess
    else:                                        spillover = 0                    // ordinary slack
    ```
  - `.postEnd`: spillover absorbs the entire `remaining` (the final period is final — there is
  no future "midnight" at which slack would be folded in by the walker, so we collapse to
  symmetric live coupling for this state): `spillover = remaining`.
  - `.preStart`, `.paused`: `spillover = 0`. (`remaining` is also 0 in both states per step 9 /
  step 2, so this is a no-op — explicit for clarity.)

  **Reset interaction.** The spillover's input honors `lastResetDate` (§A.5.6 "Reset
  interaction"): the input is recomputed from post-reset expenses only
  (`spilloverRemaining = effectiveAllocation − Σ expenses in
  [max(effectivePeriodStart, lastResetDate ?? .distantPast), effectivePeriodEnd)`), and when
  `lastResetDate >= effectiveEndExclusive` (reset after the budget ended), `spillover = 0`.
  Step 9's `remaining` is **not** affected.
13. **Assemble `carryOver`.** `carryOver = walkerSum + currentPeriodSpillover` (recurring).
  `carryOver = nil` for Specific Dates (handled in §A.4.2).
14. **Return** the snapshot.

### A.4.2. Specific Dates branch

`.specificDates` has one window (the calendar days from `startDate` through `endDate` inclusive,
both required), one allocation, no recurrence (§2.5). Per §A.4.0 the algorithm represents this
internally as the half-open `[effectiveStartDate, effectiveEndExclusive)` for uniformity with
recurring math.

1. Pre-start short-circuit already handled in step 2 above.
2. `effectiveAllocation = allocationChanges.sorted { ($0.effectiveFrom, $0.lastModified) < ($1.effectiveFrom, $1.lastModified) }.last?.amount ?? 0`
  (latest-wins by `effectiveFrom`, with `lastModified` as the tiebreak; §5.3 / briefing §6.6
   item 7, §A.2.2). The walker is bypassed entirely; allocation history is consulted only for
   its most recent entry. In normal flow there is exactly one entry (per §A.6.2 step 1 —
   Specific Dates allocation edits mutate the single row), so the `lastModified` tiebreak is
   defensive against the rare cross-device duplicate where two devices each inserted their own
   row before sync.
3. `windowExpenses = sum of e.amount for e in expenses where effectiveStartDate <= e.date < effectiveEndExclusive`.
  (Half-open per §A.4.0; covers every calendar day from `startDate` through `endDate` inclusive.)
4. `remaining = effectiveAllocation − windowExpenses`.
5. `carryOver = nil`. The signed cumulative chip is not surfaced for this type (§A.5.1; briefing
  §2.5 "Specific Dates type semantics" and §6.6 "Specific Dates type" items 1, 5, 6 for the
   Carry-over / Reset Carry-Over / `isCarryOverEnabled` carve-outs). Note: `main-prd.md` §6.7
   does not yet contain the Specific Dates carve-out — that doc sync lands with the rewrite
   (briefing §2.11). The asymmetric spillover rule (§A.5.6) does not apply — Specific Dates has
   only one period, so the concept of "Carry-over from prior periods" is meaningless.
6. `effectivePeriodStart = effectiveStartDate`; `effectivePeriodEnd = effectiveEndExclusive`.
7. `lifecycleState = (now >= effectiveEndExclusive) ? .postEnd : .active`. Note `>=` (not `>`):
  matches §A.4.1 step 11 priority 1. Pause/Resume cannot apply (§2.5 / briefing §6.6 item 8) —
   if a stray `LifecycleEvent` exists from a CloudKit write or UI bug, it is ignored.
8. `isCarryOverEnabled` and any `LifecycleEvent`s are **ignored** regardless of stored value.

---

## A.5. Helper algorithms

**User actions / expectations this section addresses:**

- Editing allocation across multiple periods and having each prior period keep the allocation it
had at the time.
- Adding a back-dated expense to any prior active period and seeing the chip update.
- Pausing/Resuming in arbitrary patterns; the chip freezes correctly across paused stretches.
- Resetting Carry-Over and never seeing pre-reset prior periods contribute again.
- Voice query / chip parity is preserved across every helper.

### A.5.1. Period boundary math — `PeriodCalculator`

`PeriodCalculator.periodStart`, `periodEnd`, and `periodBoundaries` (already in the codebase) are
kept **as-is** for the four recurring cases. They are pure date math, take an explicit `Calendar`,
and need no change for the rewrite.

`**.specificDates` is intentionally not added to `PeriodCalculator`** — that type has no
recurring boundaries to enumerate, and the snapshot function handles it directly (§A.4.2).
Adding it would force a meaningless `nextBoundary` calculation. The compiler-level signal is
that callers must switch exhaustively before calling `PeriodCalculator`. Suggested pattern:

```swift
extension BudgetPeriod {
  /// Returns `self` typed as a recurring case, or `nil` for `.specificDates`.
  var asRecurring: RecurringBudgetPeriod? { ... }
}

enum RecurringBudgetPeriod { case daily, weekly, biweekly, monthly }
```

Or simply have `PeriodCalculator` accept `RecurringBudgetPeriod`. Either approach is fine; the
key constraint is that `PeriodCalculator` never receives `.specificDates`.

### A.5.2. `allocationInEffect(at:history:)`

```swift
static func allocationInEffect(
  at date: Date,
  history: [AllocationChange]   // any order; sorted internally
) -> Decimal {
  // Primary sort: effectiveFrom ascending. Secondary (tiebreak): lastModified ascending so the
  // later writer wins when two rows share an effectiveFrom (cross-device race; see §A.2.2).
  let sorted = history.sorted { lhs, rhs in
    if lhs.effectiveFrom != rhs.effectiveFrom {
      return lhs.effectiveFrom < rhs.effectiveFrom
    }
    return lhs.lastModified < rhs.lastModified
  }
  // The "in-effect" entry is the latest with effectiveFrom <= date.
  let applicable = sorted.last(where: { $0.effectiveFrom <= date })
  return applicable?.amount ?? sorted.first?.amount ?? 0
}
```

Two fallbacks are deliberate:

- `applicable == nil` can only happen if `date < sorted.first?.effectiveFrom`, which means we
are querying a date strictly before the budget started. The walker should never do this
(walkStart is bounded below by `effectiveStartDate`). The `sorted.first?.amount` fallback is
defensive against malformed history (e.g., a future `effectiveFrom` set during a paused-period
edit when the storage convention places the entry past `now`).
- `?? 0` is the last-resort floor; a budget with zero allocation history is malformed but the
algorithm should not crash.

**Latest-wins semantics within a period.** When the user edits allocation, the call site finds
`currentPeriodStart` and:

- If `history` contains an entry with `effectiveFrom == currentPeriodStart`: **mutate its
`amount` and set `lastModified = now`** (no new entry).
- Else: insert a new `AllocationChange(effectiveFrom: currentPeriodStart, amount: newValue)`
(its `lastModified` defaults to `Date()` on insert).

On a single device this guarantees there is never more than one entry per period boundary and
that the latest edit within the same period wins (briefing §6.2 item 3). Across devices, two rows at the same
`effectiveFrom` can briefly coexist after CloudKit sync; the `lastModified` tiebreak in the sort
above resolves them deterministically. When paused, `currentPeriodStart` refers to the paused
period's start; that entry is "noise" until the budget resumes (paused periods contribute 0 to
carry-over regardless of allocation value — see §2.1, §5.5).

### A.5.3. Carry-over walker — `walkCarryOver(...)`

The walker iterates all **completed** prior periods between `walkStart` and `currentPeriodStart`,
folding `(allocation in effect − expenses in window)` for each active period.

```swift
static func walkCarryOver(
  effectiveStartDate: Date,         // start-of-day-normalized (§A.4.0)
  effectiveEndExclusive: Date,      // start-of-day(endDate + 1.day), or .distantFuture (§A.4.0)
  lastResetDate: Date?,
  currentPeriodStart: Date,
  allocationChanges: [AllocationChange],
  lifecycleEvents: [LifecycleEvent],
  expenses: [ExpenseItem],
  period: RecurringBudgetPeriod,
  weekStart: Weekday,
  biweeklyAnchor: Date,
  calendar: Calendar
) -> Decimal {
  let walkStart = max(effectiveStartDate, lastResetDate ?? .distantPast)
  guard walkStart < currentPeriodStart else { return 0 }

  let boundaries = PeriodCalculator.periodBoundaries(
    from: walkStart, to: currentPeriodStart,
    period: period, weekStart: weekStart, biweeklyAnchor: biweeklyAnchor,
    calendar: calendar
  )

  var carryOver: Decimal = 0
  for (i, boundary) in boundaries.enumerated() {
    let rawNext: Date = (i + 1 < boundaries.count)
      ? boundaries[i + 1]
      : PeriodCalculator.periodEnd(containing: boundary, ...)

    // Effective window: clamped at effectiveStartDate (partial first period) and
    // effectiveEndExclusive (partial last period).
    let effStart = max(boundary, effectiveStartDate)
    let effEnd = min(rawNext, effectiveEndExclusive)
    guard effStart < effEnd else { continue }   // window collapsed; skip

    // Paused periods contribute 0 (regardless of allocation, regardless of expenses).
    // Pass `effStart` (the effectiveStartDate-clamped lower bound), not `boundary` — this matches
    // the §A.5.4 contract for the `periodStart` argument and ensures pre-start pause events
    // stored at `startDate − ε` are correctly classified as "before the first period" when
    // `startDate` falls mid-period.
    guard isActive(periodStart: effStart, periodEnd: rawNext, events: lifecycleEvents) else {
      continue
    }

    // Full per-period allocation — no proration for partial first/last periods (§2.4). The
    // initial `AllocationChange.effectiveFrom` is a natural period boundary by storage
    // convention (§A.2.2 / §A.6.1), so for the first period — boundary equals that same
    // natural boundary — the lookup at `boundary` directly returns the initial entry's full
    // per-period amount (e.g. $100/mo for a monthly budget with `startDate = June 16`: initial
    // entry at June 1, walker boundary at June 1, lookup returns $100). The `max(boundary,
    // effectiveStartDate)` clamp is **defensive** against malformed-sync-record cases where a
    // row's `effectiveFrom` sits at a mid-period date — querying at `effectiveStartDate` keeps
    // the lookup landing on the row directly. For every subsequent period `boundary >=
    // effectiveStartDate`, so the clamp is a no-op.
    let allocation = allocationInEffect(
      at: max(boundary, effectiveStartDate),
      history: allocationChanges
    )

    // Expenses outside [effStart, effEnd) are not counted — UI rejects them but the algorithm
    // clamps defensively.
    let periodExpenses = expenses
      .filter { $0.date >= effStart && $0.date < effEnd }
      .reduce(Decimal(0)) { $0 + $1.amount }

    carryOver += (allocation - periodExpenses)
  }
  return carryOver
}
```

**Key properties:**

- **Mid-period live (§2.1).** Carry-over is recomputed every time the snapshot is requested. Any
change that affects the inputs (expenses, allocation history, lifecycle events, lastResetDate,
start/end dates) flows through on the next refresh trigger.
- **Forward-only allocation edits (§2.1, §5.1).** Each iteration looks up `allocationInEffect`
for its *own* `boundary`. Editing today's allocation does not retroactively rewrite the
allocation used for any prior period.
- **Backdated expenses (§2.7, briefing §6.7 items 5–6).** The walker filters expenses fresh on
every call; changing an expense's date or amount immediately changes the sum for whichever
active period it now falls in.
- **Reset Carry-Over floor (briefing §6.3 item 4).** `walkStart = max(effectiveStartDate, lastResetDate ?? .distantPast)`
ensures prior completed periods that ended before the most recent reset are not folded into
carry-over. The current period's "remaining" is computed independently of the walker and is
unaffected by the reset floor.
- **Paused periods (§2.7, §5.5, briefing §6.7 item 7).** The walker skips paused periods
entirely. Their contribution is 0 — including any expenses that somehow ended up dated within
them.
- **No proration (§2.4, briefing §6.5 item 3).** Partial first/last periods get the full allocation.

### A.5.4. Active/paused classification — `isActive(...)`

The lifecycle history is interpreted at **period granularity**. The same function classifies any
period — the current one or any historical period iterated by the walker.

**Caller contract.** `periodStart` is the **effective** lower bound for the period — that is,
`max(naturalPeriodStart, effectiveStartDate)` (per §A.4.0). Callers (both the main algorithm
§A.4.1 step 7 and the walker §A.5.3) must clamp before invoking. This ensures pre-start pause
events stored at `startDate − ε` (per §A.2.3) are correctly classified as "before the first
period" even when `startDate` falls mid-period and the natural period boundary is earlier than
`startDate`.

```swift
static func isActive(
  periodStart: Date,   // pass max(naturalPeriodStart, effectiveStartDate); see caller contract
  periodEnd: Date,
  events: [LifecycleEvent]   // any order; sorted internally
) -> Bool {
  // Sort by date ascending. LifecycleEvent has no secondary tiebreak field; same-`date`
  // collisions are equivalence-class duplicates (see §A.2.3) and any sort order produces the
  // same classification result.
  let sorted = events.sorted { $0.date < $1.date }

  // Rule 1: any event in [periodStart, periodEnd) → this period is ACTIVE (§5.5 "Period granularity").
  if sorted.contains(where: { $0.date >= periodStart && $0.date < periodEnd }) {
    return true
  }

  // Rule 2: no events in this period — defer to the latest event strictly before periodStart.
  // No prior event ⇒ initial state is active.
  guard let lastPrior = sorted.last(where: { $0.date < periodStart }) else { return true }
  return lastPrior.kind == .resume
}
```

Why this is correct against the briefing's invariants (§5.5):

- **Pause-action period is active.** Rule 1: the event sits in `[periodStart, periodEnd)` →
return true.
- **Resume-action period is active in full.** Same as above — Rule 1 returns true.
- **Periods strictly after a pause-action period are paused** — until a Resume occurs. Rule 2:
the latest prior event is the pause → return false.
- **Periods strictly after a resume-action period are active** — until another Pause occurs.
Rule 2: the latest prior event is the resume → return true.
- **Multiple events in one period.** Rule 1 returns true (the period is active). The
"post-period state" only matters for the *next* period, which will look up the latest event
before it — which is the last of the in-this-period events sorted by date. Both pause-then-resume
and resume-then-pause within one period are handled correctly by Rule 2 applied to the *next*
period.
- **Pre-start pause.** The pause is stored with `date == effectiveStartDate − ε` (§A.2.3).
Callers pass the *effective* lower bound `max(naturalPeriodStart, effectiveStartDate)` for the
first period (per the caller contract above) — which equals `effectiveStartDate` whenever
`naturalPeriodStart <= effectiveStartDate` (always true; daily/weekly/biweekly anchor on
`effectiveStartDate`, monthly's natural boundary is at-or-before it). The event at
`effectiveStartDate − ε` is **not** in `[effectiveStartDate, periodEnd)` — Rule 1 returns
false — and Rule 2 finds it as the latest prior event, returning false (paused). The first
period is therefore paused, consistent with "from `startDate` onward the budget is in a paused
state until the user resumes" (§5.5). Without the caller-side clamp, a monthly budget with a
mid-month `startDate` (e.g. `April 15`) would land the pre-start event inside the first
natural period (`April 14 23:59:59.999...` ∈ `[April 1, May 1)`) and Rule 1 would incorrectly
return active. The clamp is the fix. Both the storage-side normalization (event at
`effectiveStartDate − ε`) and the caller-side clamp (`isActive` receives
`max(natural, effectiveStartDate)`) are required; together they make the carve-out robust to
both the mid-month-`startDate` case and the malformed-sync-record fallback case.

**Concurrent device convergence (briefing §6.2 item 12 / §6.7 item 13).** Because `isActive`
re-sorts the events on every call, it is insensitive to the order in which CloudKit delivers
them. Live post-`startDate` actions from independent devices produce naturally distinct `date`
values (wall-clock-now doesn't collide to the nanosecond across devices in practice), so the
sort fully orders them and Rule 2's "latest prior event" lookup is deterministic. The one
realistic same-`date` collision is two pre-start pauses across devices — both store
`date == effectiveStartDate − ε`. These rows are equivalence-class duplicates: same `kind`
(both pause), so whichever the sort picks last yields the same Rule 2 result (paused). No
disambiguating `lastModified` field is needed (§A.2.3).

### A.5.5. Display contract — what the algorithm returns vs. what the UI renders

This algorithm returns numbers; the UI translates `lifecycleState` into chip presentations
(§2.9). The contract:


| `lifecycleState` | `remaining`                   | `carryOver` (recurring; `nil` for Specific Dates)             | Expected UI presentation       |
| ---------------- | ----------------------------- | ------------------------------------------------------------- | ------------------------------ |
| `.preStart`      | 0                             | 0                                                             | "Starts on X" overlay; value 0 |
| `.active`        | `allocation − thisPeriodSum`  | `walkerSum + spillover` (§A.5.6 asymmetric rule)              | Standard chip(s)               |
| `.paused`        | 0                             | `walkerSum` (frozen at last active period; spillover = 0)     | "Paused since X" overlay       |
| `.postEnd`       | `allocation − finalPeriodSum` | `walkerSum + remaining` (final-period contribution folded in) | "Ended on X" overlay; frozen   |


"Frozen" in `.postEnd` is **intrinsic to the algorithm** (because `effectiveNow = min(now, effectiveEndInclusive)` stops advancing) rather than a UI-only effect — but backdated edits
within `[effectiveStartDate, effectiveEndExclusive)` still recompute (§2.9, briefing §6.5 item 2). The same
holds for `.paused`: the value "freezes at the most-recent-pause" simply because subsequent
periods are paused and skipped, and backdated edits to prior active periods recompute (§5.5,
briefing §6.7 item 5).

### A.5.6. Asymmetric live coupling — `currentPeriodSpillover`

In `.active` state, Carry-over is **not** purely a function of completed prior periods. It also
absorbs the **committed** portion of the current period's net in real time. This is the
"asymmetric live coupling" rule.

```swift
static func currentPeriodSpillover(
  remaining: Decimal,
  effectiveAllocation: Decimal,
  lifecycleState: LifecycleState
) -> Decimal {
  switch lifecycleState {
  case .preStart, .paused:
    return 0
  case .active:
    if remaining < 0 {
      return remaining                              // overspend — negative spillover
    } else if remaining > effectiveAllocation {
      return remaining - effectiveAllocation        // add-funds excess — positive spillover
    } else {
      return 0                                      // ordinary slack — not yet committed
    }
  case .postEnd:
    return remaining                                // final period — fold everything in
  }
}
```

**Three regions for the current period's `remaining` in `.active` state:**


| `remaining` value (live)                                     | Spillover                                    | Carry-over display                              |
| ------------------------------------------------------------ | -------------------------------------------- | ----------------------------------------------- |
| `0 <= remaining <= effectiveAllocation` (ordinary use)       | `0`                                          | `walkerSum` only                                |
| `remaining < 0` (overspend)                                  | `remaining` (negative)                       | `walkerSum + remaining`                         |
| `remaining > effectiveAllocation` (add-funds excess, F-6.01) | `remaining - effectiveAllocation` (positive) | `walkerSum + (remaining - effectiveAllocation)` |


**Why asymmetric.** The "in-period commitment" mental model is the user-facing rationale.
Overspending today and deliberately adding funds (F-6.01) are both *committed* actions — they
reflect real user decisions that change the cumulative position. Ordinary mid-day slack
(`remaining > 0`) is *provisional* — the user might still spend more before the period closes, so
keeping it out of Carry-over until the period actually completes prevents over-confident "I'm
ahead!" displays mid-day. Loss-aversion: bad news lands immediately, good news waits for the
period to close.

**Worked example.** Daily $20 budget, +$5 carry-over from prior days, $10 spent today so far.


| Event                                                         | `remaining` | `spillover` | Displayed `carryOver` |
| ------------------------------------------------------------- | ----------- | ----------- | --------------------- |
| State described                                               | $10         | $0          | +$5                   |
| User adds $11 expense                                         | −$1         | −$1         | **+$4**               |
| User undoes that $11 expense                                  | $10         | $0          | **+$5** (snaps back)  |
| User adds $30 via Add Funds (negative-amount expense, F-6.01) | $40         | $20         | **+$25**              |
| User then spends $30                                          | $10         | $0          | **+$5** (cancels out) |


Each state transition is live — the snapshot is recomputed and the chip updates as soon as the
write is persisted. The walker does not change; only the snapshot's final assembly does (§A.4.1
step 12 → step 13).

**Period-boundary continuity.** When the current period closes and the next snapshot is taken,
the just-closed period becomes a completed prior period in the walker's range. There is no
double-counting: the walker iterates `[walkStart, newCurrentPeriodStart)`, which now includes the
just-closed period. The spillover from the *new* current period starts fresh at 0. Net jump at
midnight = `(remaining_at_close − spillover_at_close)`:

- Closed with overspend (`remaining < 0`): walker folds in `remaining`, spillover was already
`remaining`. Jump = 0. **Smooth.**
- Closed with add-funds excess (`remaining > allocation`): walker folds in `remaining`, spillover
was `remaining - allocation`. Jump = `allocation`. (The unconsumed allocation portion of the
period flows in at close — the "good news" half of the asymmetric rule.)
- Closed with ordinary use (`0 <= remaining <= allocation`): walker folds in `remaining`,
spillover was 0. Jump = `remaining`. (Standard "today's slack becomes tomorrow's cushion.")

**Why the `.postEnd` rule is different.** There is no future period close to fold the slack in,
so the rule collapses to "everything counts now" (`spillover = remaining`). This matches the
briefing's "frozen at final tally" requirement (§2.9, §6.5).

**Why `.paused` spillover is 0.** Step 9 forces `remaining = 0` for paused periods, so the
`.active` rule would have returned 0 anyway. Explicit case for clarity.

**Reset interaction.** A manual reset (`lastResetDate`, §A.6.4/§A.6.5) trims the walker — and
it equally trims the spillover. The `currentPeriodSpillover` function itself is unchanged (it
stays a pure 3-input classifier); the snapshot assembly feeds it a *reset-aware* input:

- `spilloverRemaining = effectiveAllocation − Σ expenses in
  [max(effectivePeriodStart, lastResetDate ?? .distantPast), effectivePeriodEnd)` — pre-reset
  expenses are excluded while the full allocation is still awarded, mirroring the walker's
  no-proration convention for the period containing a reset (§A.5.3). The input therefore
  equals the contribution the walker will compute for this period once it closes, so committed
  overflow carries continuously across the boundary (period-boundary continuity above) and a
  mid-period reset zeroes a current-period deficit from the Carry-over chip immediately.
- When `lastResetDate >= effectiveEndExclusive` — the reset was performed after the budget
  ended, reachable only in `.postEnd` because the write paths stamp `now` — `spillover = 0`.
  Without this carve-out, the symmetric `.postEnd` rule would re-fold the final period's
  remaining right back in (after Reset Budget deletes the expenses, that would be the *full
  final allocation*), making post-end resets ineffective forever since the final period never
  closes.
- Step 9's `remaining` is **not** reset-aware — the post-reset rebound (§A.6.4) intentionally
  keeps the current envelope reflecting all of today's expenses.

---

## A.6. State changes from user actions

**User actions / expectations this section addresses:**

- Create Budget
- Edit Allocation (recurring and Specific Dates)
- Edit Start Date / End Date
- Reset Carry-Over (manual)
- Reset Budget (destructive — deletes expenses)
- Pause Budget
- Resume Budget
- Delete Budget

The algorithm is pure; the changes that *feed* it live at write sites scattered through the app.
This section enumerates those writes and the small amount of code each requires. Each is its own
`ModelContext.save()` — no need for orchestrated multi-step persistence like the existing
`refreshAndSave`.

**Project-wide rule — `lastModified` bump.** Every user-initiated write below also sets
`budget.lastModified = now` in the same `ModelContext.save()`. This matches the convention for
the main entities (`Budget`, `ExpenseItem`): any user action that edits existing data or writes
new data updates `lastModified`. Per-section steps below omit this for brevity except where the
choice of timestamp needs explanation.

Additionally, when a write inserts or mutates an `AllocationChange` row, that row's own
`lastModified` is set to `now` in the same `save()`. This is what makes the cross-device
tiebreak in §A.5.2 deterministic — the later writer's row carries the later `lastModified` and
wins the sort when two devices land entries at the same `effectiveFrom`. Per-section steps below
mention this only where the distinction matters (e.g. mutating an existing `AllocationChange`
vs. inserting a new one).

`LifecycleEvent` rows have **no `lastModified` field** — they are append-only and same-`date`
cross-device collisions are equivalence-class duplicates (§A.2.3), so no tiebreak storage is
needed.

(Background CloudKit merges do **not** bump `lastModified` on any entity.)

### A.6.1. Create budget

1. Insert a `Budget` row with the user's chosen fields (name, period, currency,
  `isCarryOverEnabled`, `startDate`, `endDate` if applicable). The UI saves `startDate` and
   `endDate` as start-of-day in the user's calendar (per §A.4.0).
2. Insert one `AllocationChange` linked to the budget, with `amount = initialAllocation`. The
  `effectiveFrom` value must align with the natural period boundary of the period containing
   `effectiveStartDate` — this is what allows §A.5.2's "mutate vs. insert" rule to correctly
   recognize a future same-period edit (see §A.2.2 storage rules + "Why monthly mid-month uses
   the month boundary" note):
  - **All period types:** `effectiveFrom = effectiveStartDate` (what the Add-mode save path
  actually writes — see the data-models spec "Initial AllocationChange row on Budget
  creation"). For monthly budgets created mid-month — and, since #240, weekly budgets whose
  `startDate` is off the global `weekStart` grid — this value sits *inside* the first grid
  period rather than on its boundary; the read paths are built for that (step 8's
  `max(...)` clamp, the walker's earliest-row fallback, and the §A.6.2 governing-row edit
  key).
   (Since #240 the weekly grid is global, so a weekly `effectiveFrom = effectiveStartDate` may
   sit mid-grid; that is fine — the read path looks up allocation at
   `max(currentPeriodStart, effectiveStartDate)` and the walker's boundary lookups use the
   earliest-row fallback, so the row is found either way. See §A.6.2 for the matching edit-key
   rule.) The `lastModified` field defaults to `Date()` on insert.
3. `save()`.

`.specificDates` budgets require both `startDate` and `endDate` from the UI; otherwise Save is
gated (§2.4 / §5.3).

### A.6.2. Edit allocation

In every branch below, **set the row's `lastModified = now`** on insert *and* on mutate. This is
the tiebreak for cross-device duplicates (§A.5.2).

1. If `period == .specificDates`: **mutate** the single `AllocationChange` — set both `amount`
  and `lastModified = now` (latest-wins; briefing §6.6 item 7). `save()`. No other steps.
2. Else (recurring):
  - **Pre-start (`now < effectiveStartDate`).** Mutate the budget's single `AllocationChange`
   row (the initial entry — guaranteed to be the only one by the §A.2.2 storage rule for a
   never-started budget): set both `amount` and `lastModified = now`. Do **not** match by a
   specific `effectiveFrom` value or compute `currentPeriodStart` — both are meaningless
   before the budget has started, and trying to match by `effectiveFrom == effectiveStartDate`
   would miss the row for a monthly budget with a mid-month `startDate` (where the initial
   entry's `effectiveFrom` is the natural month boundary, not `effectiveStartDate` itself).
   `save()`.
  - **Normal (`now >= effectiveStartDate`).** Compute `currentPeriodStart` for `now` against
  the budget's anchors (§A.4 steps 5–6; weekly uses the caller-provided global `weekStart`).
  Compute the **edit key** `key = max(currentPeriodStart, effectiveStartDate)` — the same
  instant the snapshot's live read uses for `allocationInEffect` (§A.4.1 step 8). Find the
  **governing row**: the latest `AllocationChange` (by `(effectiveFrom, lastModified)`) with
  `effectiveFrom <= key`. If it exists and its `effectiveFrom >= currentPeriodStart` (it
  governs only the current period): **mutate it** (set both `amount` and `lastModified = now`).
  Else: **insert** a new `AllocationChange(effectiveFrom: key, amount: newValue)`. `save()`.
  For grid-aligned budgets `key == currentPeriodStart` and this is the original
  insert-or-mutate convention byte for byte. For a first period that starts mid-grid (a
  monthly budget created mid-month; a weekly budget whose `startDate` is off the global
  week grid), the rule mutates the initial `startDate` row instead of inserting a row at
  the grid boundary that the live read would shadow — guaranteeing the live read and the
  walker's closed-period lookup (boundary + earliest-row fallback) both observe the edit
  (issue #247, change `weekly-global-week-start`).
3. While paused: the normal-branch write happens; `currentPeriodStart` refers to the paused
  period. The entry has no effect until the budget resumes (§5.5, §A.5.2). The briefing notes
   that either storage convention (record at paused-period's start vs. record at the
   resume-anchored period's start) produces the same final carry-over because paused periods
   contribute 0. This design uses the **paused-period's start** for simplicity — it requires no
   lookahead to a future resume event.

No fields other than the `AllocationChange.amount` + `lastModified` (or a new `AllocationChange`
row) and `budget.lastModified` (per the §A.6 global rule) are touched.

### A.6.3. Edit `startDate` or `endDate`

1. Write the new field directly to the `Budget`. `save()`. No history table — these are
  single-valued fields.
2. The next snapshot reflects the change immediately. The walker's `walkStart`, period anchors,
  and `effectiveNow` all derive from the live values.

Edge consideration: if the user *narrows* the window (e.g. moves `endDate` earlier), expenses
dated outside the new window become orphans w.r.t. the algorithm (filtered out by the walker
and the current-period sum). The UI is responsible for warning the user; the algorithm just
clamps. Same for moving `startDate` later.

### A.6.4. Reset Carry-Over (manual)

1. Set `budget.lastResetDate = now`.
2. `save()`.

That is all. The walker's `walkStart = max(effectiveStartDate, lastResetDate)` automatically
excludes prior completed periods that ended before the reset, and the current period's
spillover input is likewise recomputed from post-reset expenses (§A.5.6 "Reset interaction"),
so the Carry-over chip reads 0 immediately after the reset — including when the current
period was in deficit, and permanently when the budget had already ended. No expenses are
deleted; no allocation history is touched.

Post-reset rebound (briefing §6.3 item 1) is automatic: the current period's `remaining = allocation − currentPeriodSpend` is independent of the walker and still reflects today's existing expenses.

### A.6.5. Reset Budget (destructive)

1. Delete every `ExpenseItem` linked to the budget.
2. Set `budget.lastResetDate = now`.
3. `save()` (single transaction).

`allocationChanges` and `lifecycleEvents` are intentionally **not** cleared. The current
allocation continues to be whatever was in effect. The current pause state continues to be
whatever it was (the briefing says Reset Budget while paused leaves the pause state alone —
briefing §6.7 item 11).

On a `.postEnd` budget, `lastResetDate >= effectiveEndExclusive` suppresses the final
period's spillover entirely (§A.5.6 "Reset interaction"), so the post-reset Carry-over is 0
rather than the rebounded final-period remaining (which, with expenses deleted, would be the
full final allocation).

### A.6.6. Pause budget

1. Resolve `effectiveDate`:
  - If `now >= effectiveStartDate`: `effectiveDate = now`.
  - If `now < effectiveStartDate`: `effectiveDate = effectiveStartDate - ε` (§A.2.3 pre-start
  carve-out).
2. Insert `LifecycleEvent(kind: .pause, date: effectiveDate)`. The row is append-only — no
   `lastModified` field, no follow-up mutations (§A.2.3).
3. `save()`.

Hidden / rejected for `.specificDates` and for budgets where `now >= effectiveEndExclusive`
(§5.5). The UI enforces this; if a stray event arrives via CloudKit, the algorithm ignores it
(§2.5).

### A.6.7. Resume budget

1. Insert `LifecycleEvent(kind: .resume, date: now)`. Append-only, no `lastModified` field
   (same as Pause; §A.2.3).
2. `save()`.

Rejected if `now >= effectiveEndExclusive` (§5.5, briefing §6.7 item 12) — UI-enforced.
Algorithm ignores any stray such event on `.specificDates`.

### A.6.8. Delete budget

Unchanged in shape — cascade-delete via the relationship — but the cascade now also removes
`AllocationChange` and `LifecycleEvent` rows (§A.2.4).

---

## A.7. Removal checklist

**User actions / expectations this section addresses:**

- (Developer-facing.) Indirectly addresses the user expectation that Reset Cadences — paused
since 2026-04-28 — never reappears in the UI. This section is the explicit deletion list that
enforces that.

To track what the rewrite *removes* from the codebase. Each item must be gone before the change
merges. This list maps to briefing §5.4 and the doc/spec sync table in briefing §2.11.

**Code:**

- `Budget.allocation: Decimal` (stored property)
- `Budget.carryOverAmount: Decimal`
- `Budget.carryOverLastProcessedDate: Date`
- `Budget.carryOverLastResetDate: Date` → renamed to `lastResetDate: Date?`
- `Budget.resetCadence: String` and its `init` parameter
- `enum ResetCadence` (whole file or section)
- `BudgetPeriod.defaultResetCadence` extension
- `BudgetCalculator.rollCarryOver(...)` and `CarryOverRollResult`
- `BudgetCalculator.checkScheduledReset(...)` and `ResetCheckResult`
- `BudgetCalculator.advanced(from:by:calendar:)` (private helper for cadence)
- `BudgetLifecycleService.refreshAndSave(...)` — replaced by a thin caller of
`BudgetCalculator.snapshot(...)` (no save needed for the read path; see §A.8)
- Tests for `rollCarryOver`, `checkScheduledReset`, `defaultResetCadence`, and any
cadence-related lifecycle scenarios

**Docs and specs** — see briefing §2.11. All updates land in the same OpenSpec change.

---

## A.8. Integration with `BudgetLifecycleService`

**User actions / expectations this section addresses:**

- (Developer-facing.) How a view body invokes the snapshot — same triggers the user already
experiences (screen appearance, `scenePhase == .active`, post-write refresh). This section
ensures the user does not see stale values after any of those triggers.

The existing service exists to orchestrate the boundary-only `rollCarryOver` → persist →
`checkScheduledReset` → persist sequence. After the rewrite, there is **no read-path persistence**
(see §A.5.3 — the walker is live and computes from inputs that already live in the database).

Two options:

1. **Delete `BudgetLifecycleService` entirely.** Call sites switch to
  `BudgetCalculator.snapshot(...)` directly. Pure, no `ModelContext` needed at the read site.
2. **Keep it as a thin facade.** `refreshAndSave` becomes `snapshot(_:settings:context:)` which
  just calls `BudgetCalculator.snapshot(...)` and returns. The `context` parameter is unused on
   the read path. Useful only if we anticipate future side-effects on read (none planned).

**Recommendation: Option 1.** The service was a useful seam when persistence was tied to reads;
once reads are pure, the indirection adds nothing. View bodies invoke the calculator directly
via `.task` and `.onChange`, the same triggers they already use. The "single entry point"
property (briefing §4.3) is preserved by the snapshot function's contract.

Write paths (§A.6) live at user-action call sites — those are simple enough that they don't
need a service wrapper; they're typically one to three lines plus `save()`.

---

## A.9. Edge case walkthroughs

**User actions / expectations this section addresses:**

- Every user-facing scenario enumerated in briefing §6: expense lifecycle, allocation lifecycle,
reset, start/end dates, Specific Dates type, pause/resume, display-only edits, and
interactions with future features (Add Funds, Voice query, analytics).
- The ★-marked cases are the ones whose handling is most likely to surprise users; they are
walked explicitly.

This section walks the briefing §6 list. Each item names the section in this document that
makes it work, and where useful gives a small worked example. Items marked **★** are the
briefing's "design flaw exposers" — they are walked explicitly.

### A.9.1. Expense lifecycle (briefing §6.1)


| #   | Case                                | Handled by                                                                                                           |
| --- | ----------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| 1   | Add in current period               | `remaining` recomputes on next snapshot (§A.4.1 step 9).                                                             |
| 2   | Add backdated to prior period       | Walker re-folds on next snapshot (§A.5.3).                                                                           |
| 3   | Edit amount in current period       | Same as 1.                                                                                                           |
| 4   | Edit amount in prior period         | Same as 2.                                                                                                           |
| 5   | Edit date across period boundary    | Both old period and new period recompute via the walker (§A.5.3).                                                    |
| 6   | Delete in current period            | Same as 1.                                                                                                           |
| 7   | Delete in prior period              | Same as 2.                                                                                                           |
| 8   | Sign-flip (add-funds)               | Algorithm treats negative amounts uniformly (the sum includes them with sign). Matches F-6.01 semantics.             |
| 9   | Date outside `[startDate, endDate]` | UI rejects; algorithm also clamps because the walker's window and current-period sum both reject out-of-range dates. |


### A.9.2. Allocation lifecycle (briefing §6.2)


| #        | Case                                                                | Handled by                                                                                                                                                                                                                                            |
| -------- | ------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1        | Single edit, current period day 1                                   | New `AllocationChange` at `currentPeriodStart`. Walker's iteration of prior periods is unaffected.                                                                                                                                                    |
| 2        | Single edit mid-period                                              | Same as 1 — the edit takes effect at `currentPeriodStart`, not mid-period (§5.1).                                                                                                                                                                     |
| 3        | Multiple edits in same period                                       | Replace existing entry at `currentPeriodStart` (§A.5.2). Latest wins; prior figure not retrievable (briefing §6.2 item 3).                                                                                                                            |
| 4        | Two edits in different periods                                      | Two entries; walker picks the correct one per period via `allocationInEffect` (§A.5.2).                                                                                                                                                               |
| 5        | Decreasing allocation                                               | No special case — `allocation − expenses` can be negative. Already handled.                                                                                                                                                                           |
| **6 ★**  | Edit then backdated expense to a period BEFORE the most recent edit | Walker uses `allocationInEffect(at: boundary)` for each period; pre-edit periods get the OLD allocation. **Verified in §A.5.3.**                                                                                                                      |
| 7        | Edit then backdated expense to period BETWEEN two edits             | Same mechanism as 6.                                                                                                                                                                                                                                  |
| **8 ★**  | Edit then manual Reset Carry-Over                                   | Reset sets `lastResetDate = now`; walker's `walkStart = max(startDate, lastResetDate)` skips pre-reset periods entirely, so pre-reset allocation history is not consulted.                                                                            |
| 9        | Reset Carry-Over then allocation edit                               | Edit lands at current `currentPeriodStart` (post-reset). Walker has no completed periods if reset is recent.                                                                                                                                          |
| 10       | Edit while carry-over is negative                                   | No special case.                                                                                                                                                                                                                                      |
| 11       | Edit on a budget with zero prior periods                            | Walker boundary list is empty → carry-over 0; edit affects only the current period's `remaining`.                                                                                                                                                     |
| **12 ★** | Concurrent edits on two devices via CloudKit                        | Both `AllocationChange` rows arrive after sync; sorted by `(effectiveFrom, lastModified)` on read. Same-`effectiveFrom` ties resolved by **later `lastModified` wins** (§A.5.2). Snapshot converges to a specific value, deterministically (§A.10.4). |


### A.9.3. Reset / lifecycle (briefing §6.3)


| #   | Case                                                                         | Handled by                                                                                                                                                                                                                                                                                                                                                                |
| --- | ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Manual reset + immediate rebound                                             | §A.6.4. Current period's `remaining` is independent of the walker.                                                                                                                                                                                                                                                                                                        |
| 2   | Reset, then edit, then add                                                   | Trivially composes (§A.6.4 → §A.6.2 → §A.6.1 expense add).                                                                                                                                                                                                                                                                                                                |
| 3   | No surviving scheduled-reset code path after rewrite                         | §A.7 removal checklist.                                                                                                                                                                                                                                                                                                                                                   |
| 4   | Edit pre-reset expense in a *prior completed* period → carry-over unaffected | `walkStart = max(effectiveStartDate, lastResetDate)` excludes any prior completed periods that ended before `lastResetDate` (§A.5.3). The period in which the reset itself occurred is still walked once it completes — briefing §6.3 item 4 requires earlier periods to be unaffected, not the reset period. Briefing §6.3 item 1 documents the in-reset-period rebound. |


### A.9.4. Start Date (briefing §6.4)


| #       | Case                                         | Handled by                                                                                            |
| ------- | -------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| **1 ★** | `startDate` in the future, `now < startDate` | Step 2 short-circuit returns `.preStart` snapshot (§A.4.1).                                           |
| 2       | `startDate` in the past (backfill)           | Walker iterates from `startDate` forward through completed periods.                                   |
| 3       | `startDate == nil` at read time              | Fallback to `createdAt` in step 1 (§A.4.1, §A.2.1). Safety net only.                                  |
| 4       | Weekly, `startDate == Wednesday`             | Since #240: the grid is the global `weekStart` (e.g. Sunday); the Wednesday `startDate` only clips the first period (§A.4.1 steps 5–6). |
| 5       | Biweekly, `startDate == some Monday`         | `biweeklyAnchor = startDate`; biweekly cycles align to that Monday, independent of `weekStart`.       |


### A.9.5. End Date (briefing §6.5)


| #       | Case                                                                     | Handled by                                                                                                                                                                                                                                                                                                                                |
| ------- | ------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **1 ★** | `now > endDate`                                                          | `effectiveNow = min(now, effectiveEndInclusive)` (step 4) — clamps to the start of the last active day so `periodStart(containing: effectiveNow)` lands inside the final active period. Walker stops at the period containing the final active day. Chip frozen. `.postEnd` fires once `now >= effectiveEndExclusive` (§A.4.0 + step 11). |
| 2       | Add backdated expense after `endDate` (within window)                    | Algorithm folds it in — the walker / current-period sum recompute. Chip updates.                                                                                                                                                                                                                                                          |
| 3       | `endDate` mid-period — no proration, full allocation                     | Walker's allocation lookup uses the period's natural start; no proration anywhere (§A.5.3).                                                                                                                                                                                                                                               |
| 4       | Specific Dates past its `endDate`                                        | Specific-dates branch (§A.4.2) returns `.postEnd` with frozen `remaining` once `now >= effectiveEndExclusive`.                                                                                                                                                                                                                            |
| 5       | Expense dated exactly on `endDate` (e.g. May 15 14:00, endDate = May 15) | Included. Per §A.4.0, `effectiveEndExclusive = May 16 00:00`; the expense's date is in `[effectiveStartDate, May 16 00:00)`.                                                                                                                                                                                                              |


### A.9.6. Specific Dates type (briefing §6.6)

All cases handled by the specific-dates branch in §A.4.2. Highlights:

- **★ In-progress (case 1):** `remaining = allocation − sumOfExpensesInWindow`; `carryOver = nil`.
Updates live as expenses change.
- **Allocation edit (case 7):** latest-wins via replace-the-only-entry (§A.6.2 step 1).
- `**isCarryOverEnabled` / Reset Carry-Over (cases 5, 6):** UI hides; algorithm ignores any
stored value.
- **Pause / Resume (case 8):** UI hides; algorithm ignores any stray `LifecycleEvent`.

### A.9.7. Pause / Resume (briefing §6.7)


| #       | Case                                                               | Handled by                                                                                                                                                                                                                        |
| ------- | ------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1       | Pause/resume applies in the period it occurred — timing irrelevant | Rule 1 of `isActive` (§A.5.4): event-containing period is always active.                                                                                                                                                          |
| 2       | Pause-action period calculates normally; next period stops         | Rule 1 (active) for pause-period; Rule 2 picks pause as latest prior → paused for next period.                                                                                                                                    |
| 3       | Resume-action period activates in full                             | Rule 1 — active by virtue of containing the event.                                                                                                                                                                                |
| 4       | Carry-over carries forward across resume                           | Walker iterates all completed active periods; pause-action period contributes; paused periods skip; resume-action period (when completed) contributes.                                                                            |
| **5 ★** | Backdated expense to prior active period while paused              | Walker re-folds that prior period on next snapshot. Period is active (it was active when the events were laid down) so the contribution counts.                                                                                   |
| **6 ★** | Backdated expense to prior active period, then resume              | Same as 5. The resume-action period's "starting" carry-over inherits the recomputed sum.                                                                                                                                          |
| 7       | Backdated expense dated inside a paused period                     | UI rejects (date picker bounds); algorithm clamps via the walker's `isActive` skip.                                                                                                                                               |
| 8       | Multiple pause/resume cycles                                       | Walker iterates all periods; per-period classification is independent.                                                                                                                                                            |
| **9 ★** | Pause → allocation edit → Resume                                   | Edit records `AllocationChange` at the paused-period's start (§A.6.2 step 3). Walker skips paused periods, so the entry has no effect until the resume-action period inherits it via `allocationInEffect(at: resumePeriodStart)`. |
| 10      | Manual Reset Carry-Over while paused                               | `lastResetDate = now`. Pause state unchanged. On resume, walker `walkStart = lastResetDate`.                                                                                                                                      |
| 11      | Reset Budget while paused                                          | Expenses deleted; `lastResetDate = now`. Pause state unchanged.                                                                                                                                                                   |
| 12      | Pause then set `endDate`                                           | `.postEnd` precedence over `.paused` in step 11 of §A.4.1. Chip already frozen by the prior pause; `endDate` makes terminal.                                                                                                      |
| 13      | Concurrent pause on one device, resume on another                  | Both events sync via CloudKit; sorted by `date` on read (§A.2.3, §A.5.4). Live cross-device actions produce naturally distinct `date` values, so the sort fully orders them. The only same-`date` collision in practice is two pre-start pauses across devices, which are equivalence-class duplicates. No phantom paused period.               |
| 14      | Pause attempted on `.specificDates`                                | UI hides. Algorithm ignores any stray event (§A.4.2 step 7).                                                                                                                                                                      |
| 15      | Pause display value can still change via backdated edits           | Walker recomputes on every snapshot. The "frozen" chip is frozen w.r.t. clock advancement only.                                                                                                                                   |
| 16      | Pause while `startDate` in the future                              | Event stored at `startDate - ε` (§A.2.3 carve-out). First period is paused via Rule 2 of `isActive`.                                                                                                                              |


### A.9.8. Display / non-math edits (briefing §6.8)

- Toggling `isCarryOverEnabled`: no algorithmic effect (display-only). Snapshot unchanged.
- Editing `name`: writes `lastModified`; no math change.

### A.9.9. Future-feature interactions (briefing §6.9)

- **F-6.01 Add Funds:** negative `ExpenseItem.amount` flows through the sum naturally.
- **F-7.03 Voice query:** consumer calls `snapshot(...)` and reads `remaining` / `carryOver`. By
construction, this is the value the chip shows.
- **F-8.02 analytics:** out of scope here. The new events (`budget_paused`, `budget_resumed`,
`budget_edited.{allocation,start_date,end_date}_changed`) are fired by the write-site call
sites in §A.6, not by the algorithm.

---

## A.10. Test plan outline

**User actions / expectations this section addresses:**

- (Developer-facing.) Coverage map for the implementation phase. Every numbered user-facing
scenario in briefing §6 (and §A.9 above) gets at least one automated test, so user-visible
regressions in chip math are caught before they ship.

This is a sketch — the implementation change will produce the full Swift Testing suites. The
intent is that every numbered item in briefing §6 (and §A.9 above) has at least one test.

### A.10.1. Unit tests on `BudgetCalculator.snapshot(...)`

Group by lifecycle state, with `Calendar(identifier: .gregorian)` pinned to UTC for
determinism:

1. **Pre-start.** `now < startDate` → `.preStart`, `remaining == 0`, `carryOver == 0` (or `nil`
  for specificDates). One test per period type.
2. **Active, no prior periods.** `now` in the first period; verify `remaining` against several
  expense scenarios (none, single, multiple, add-funds). `carryOver == 0`.
3. **Active, with completed prior periods.** Walker correctness:
  - All periods active, no allocation changes → `carryOver == sum of (allocation − periodSpend)`.
  - All periods active, allocation changes between periods → each period uses its own allocation.
  - Backdated expense added to a prior period → walker reflects updated sum.
  - **★** Allocation edit then backdated expense to pre-edit period → pre-edit allocation used.
  - **★** Allocation edit then manual reset → walker `walkStart` floor honored.
4. **Paused.** `lifecycleState == .paused`; `remaining == 0`; `carryOver` equals sum of active
  periods only:
  - Pause mid-period → that period is active.
  - Multiple pause/resume cycles.
  - Backdated expense to prior active period while paused.
  - **★** Pause → allocation edit → resume.
  - Pause before `startDate` → first period paused.
5. **PostEnd.** `now >= effectiveEndExclusive`; `lifecycleState == .postEnd`; chip frozen vs.
  clock; backdated edit within `[effectiveStartDate, effectiveEndExclusive)` changes the value.
6. **Specific Dates branch.** Cases mirror briefing §6.6: pre-start, in-progress, post-end,
  backdated edits, allocation edit (latest-wins), stray pause event ignored, stray reset event
   ignored.
7. **Date arithmetic correctness.** Per-period-type anchor tests:
  - Weekly, `startDate = Wednesday` on a Sunday `weekStart` grid (partial first period, #240).
  - Biweekly, `startDate = some Monday` (anchor independent of `weekStart`).
  - Monthly, partial first period (startDate mid-month).
8. `**endDate` inclusivity (§A.4.0).** Expense dated on the last day still counts:
  - Recurring (monthly), `endDate = May 15`, expense dated `May 15 14:00` — included in
   `remaining`; chip is `.active` while `now` is in `[May 15 00:00, May 16 00:00)`;
   `.postEnd` once `now >= May 16 00:00`.
  - Specific Dates with the same `endDate` — same inclusivity rule.
9. **Asymmetric live coupling — `currentPeriodSpillover` (§A.5.6).** All in `.active` state,
  daily $20 budget, prior `walkerSum = +$5`:
  - `remaining = $10` (ordinary use) → spillover = $0, carry-over = +$5.
  - **★** `remaining = -$1` (overspend) → spillover = -$1, carry-over = **+$4**.
  - **★** `remaining = $40` (add-funds: −$20 expense, F-6.01) → spillover = $20, carry-over = **+$25**.
  - State transitions: each delta to the underlying expense set must produce the corresponding
  delta in carry-over — including snap-back to the pre-spillover value when an overspend is
  undone (delete the offending expense → carry-over returns to +$5).
  - Period-boundary continuity: at midnight on an overspend day, the walker's fold and the
  pre-close spillover cancel — the chip does **not** jump (smooth transition for committed
  overspend). At midnight on an ordinary-use day with `remaining = $15`, the chip jumps from
  +$5 to +$20 (slack flows in at close).
10. `**.postEnd` spillover (§A.5.6 collapse-to-symmetric).** Daily $20 budget, prior
  `walkerSum = +$5`, `endDate` in the past:
  - Final day spent $10 (`remaining = $10`) → carry-over = **+$15** (slack folded in because
  no future period close exists; rule collapses to symmetric).
  - Final day overspent ($25 spent, `remaining = -$5`) → carry-over = **+$0**.
  - Backdated expense edits within `[effectiveStartDate, effectiveEndExclusive)` still
  recompute (§A.5.5 "Frozen" note).

### A.10.2. Unit tests on helpers

- `allocationInEffect(at:history:)`: empty history, single entry, multiple entries before/after
date, exact-boundary lookup, **tiebreak on `lastModified` for same-`effectiveFrom` duplicates**
(see §A.10.4 for the dedicated cross-device-divergence variant).
- `currentPeriodSpillover(remaining:effectiveAllocation:lifecycleState:)` (§A.5.6):
  - `.active`, `remaining` inside `[0, allocation]` → 0.
  - `.active`, `remaining < 0` → returns `remaining`.
  - `.active`, `remaining > allocation` → returns `remaining − allocation`.
  - `.active`, `remaining == 0` and `remaining == allocation` (exact boundaries) → 0 (inclusive
  on both sides).
  - `.preStart`, `.paused` → 0 regardless of `remaining`.
  - `.postEnd` → returns `remaining` regardless of sign.
- `isActive(periodStart:periodEnd:events:)`:
  - No events → active.
  - Pause in period → active (Rule 1).
  - Resume in period → active.
  - Pause before, no resume → paused.
  - Pause before, then resume before → active.
  - Multiple events in one period (different `date` values) → "post-period state" picks last
    by `date`.
  - Sort-order independence (input shuffled, result identical).
  - **Same-`date` equivalence-class duplicates** (e.g. two pre-start pauses across devices
    both stored at `effectiveStartDate − ε`): `isActive` returns the same paused/active result
    regardless of which row the sort happens to place last, because the same-`date` rows are
    `kind`-equivalent in the only race that produces them in practice.

### A.10.3. Integration tests with SwiftData

- Round-trip a budget through an in-memory `ModelContainer`: insert budget +
`AllocationChange`s + `LifecycleEvent`s + `ExpenseItem`s, call `snapshot(...)`, verify the
result.
- Verify cascade deletes on `Budget.delete` — both `AllocationChange` and `LifecycleEvent` rows
must be removed.
- Verify the **CloudKit optionality pattern**: the stored relationship properties are typed
`[AllocationChange]?` / `[LifecycleEvent]?`; non-optional computed accessors return `[]` for a
freshly-inserted budget with no children; app code never touches the optional storage names
directly.
- Verify Reset Carry-Over: only `lastResetDate` is mutated; allocation history and lifecycle
events untouched.
- Verify Reset Budget: expenses deleted; allocation history and lifecycle events untouched;
`lastResetDate` set.
- Verify `lastModified` bump on every write: inserting or mutating an `AllocationChange` bumps
its `lastModified` to `now`; inserting or mutating any of `Budget`, `ExpenseItem`,
`AllocationChange`, or any `LifecycleEvent`-producing user action bumps `budget.lastModified`
in the same `save()`. `LifecycleEvent` rows themselves have no `lastModified` field — they are
append-only (§A.2.3).

### A.10.4. CloudKit-divergence simulation tests

Not real CloudKit; just sequencing in tests:

- **Two `AllocationChange` rows with the same `effectiveFrom`.** Construct two rows with distinct
`amount`s and distinct `lastModified` values; assert that `allocationInEffect` returns the
`amount` of the row with the **later `lastModified`** regardless of insertion order. Repeat
with the input array shuffled — result must be identical. This is the cross-device
race-with-real-consequences case — different devices can produce different `amount` values, so
disambiguation matters and `lastModified` is the tiebreak.
- **Two `LifecycleEvent` rows with the same `date` (equivalence class).** Construct two
`.pause` rows both stored at `effectiveStartDate − ε` (simulating cross-device pre-start
pauses); assert `isActive` for the first period returns paused regardless of insertion order,
and that the result is identical when the input array is shuffled. No `lastModified` tiebreak
exists for `LifecycleEvent` (§A.2.3) — the rows are interchangeable for classification.
- **A `LifecycleEvent` row whose `date` is between two other events.** Standard sort-order
invariance test for `isActive`.

The contract these tests pin down: **convergence to a stable user-visible value**, not just
"some value." For `AllocationChange` that means a single deterministic winner via the
`lastModified` tiebreak (§A.5.2). For `LifecycleEvent` it means equivalence-class outcomes —
either row in the sort produces the same classification (§A.5.4).

---

## A.11. Open implementation questions

**User actions / expectations this section addresses:**

- (Developer-facing.) None of the remaining items affect user-visible behavior — they are
implementation-shape choices. Listed here so the implementer can resolve them without
reopening this design pass.

These are intentionally **not** resolved in this document — they are minor and best decided at
implementation time, not in a design pass.

1. **Should `AllocationChange` / `LifecycleEvent` be SwiftData `@Model` entities, or `Codable`
  structs stored as a serialized blob on `Budget`?** Both work. Separate `@Model` is cleaner for
   query, conflict resolution, and CloudKit; serialized blob is simpler if we never need to query.
   Recommend `@Model` (per §A.2.2–3).
2. **Whether to keep `BudgetLifecycleService` as a thin facade or delete it outright** —
  recommended deletion in §A.8, but a one-line wrapper is harmless if call sites already use it.
3. **Should `effectiveAllocation` for `.specificDates` be the latest entry, or the
  `effectiveFrom == startDate` entry?** Recommended: latest (§A.4.2 step 2). The two diverge
   only if the user edits the allocation, and briefing §6.6 item 7 explicitly mandates latest-wins.

> **Resolved since v0.1:** "`RecurringBudgetPeriod` typing at the helper-function boundary" — the
> design commits to the wrapper enum approach in §A.5.1 (`PeriodCalculator` never receives
> `.specificDates`). No longer an open question.

---

## A.12. Revision history

**User actions / expectations this section addresses:**

- (Developer-facing.) Audit trail for design changes; helps reviewers and future implementers
understand what shifted between drafts.


| Version | Date       | Author   | Changes        |
| ------- | ---------- | -------- | -------------- |
| 1.0     | 2026-05-15 | Jimmy Ho | First version. |


