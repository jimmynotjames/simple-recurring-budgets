## Context

The app's SwiftData models (`Budget`, `ExpenseItem`) and domain enums (`BudgetPeriod`, `ResetCadence`, `Weekday`) are implemented and tested. The `AppSettings` layer provides `weekStartDay` (locale-derived, user-overridable). No business logic layer exists yet — no code computes period boundaries, remaining amounts, or carry-over rolls.

The next milestone is building screens (F-2.01, F-2.02) that display "Remaining for current Budget Period" and "Carry-over." Both screens need identical math, and the tech design doc §5.3 mandates this logic live in pure, testable services.

## Goals / Non-Goals

**Goals:**

- Provide a pure, stateless service layer that computes all budget math without SwiftData or SwiftUI dependencies.
- Cover all four `BudgetPeriod` cases (daily, weekly, biweekly, monthly) and all five `ResetCadence` cases.
- Handle multi-period catch-up (app unopened for days/weeks).
- Return structured results so callers can write back to the model without guessing derived values.
- Be thoroughly unit-testable with plain values and fixed dates — no `ModelContainer` required for calculator tests.

**Non-Goals:**

- No UI or ViewModel work in this change.
- No modifications to existing `@Model` classes or persisted schema.
- No `Budget` convenience extensions that call through to the calculator (deferred to screen-building changes).
- No background-context scheduling for the carry-over roll (ViewModels will invoke eagerly on access; background processing is a future optimization per tech design §6).

## Decisions

### 1. Two-layer architecture: `PeriodCalculator` + `BudgetCalculator`

**Decision:** Split into two structs with static methods.

- `PeriodCalculator` — Pure `Calendar`/`Date` math. Given a date, `BudgetPeriod`, `Weekday`, and `Calendar`, compute period start, period end, and enumerate boundaries between two dates. No financial concepts.
- `BudgetCalculator` — Financial math. Calls `PeriodCalculator` internally. Computes remaining, carry-over roll, and scheduled reset detection.

**Why over a single calculator:** Period boundary logic is independently useful (e.g., for date-range queries on expenses), independently testable, and conceptually distinct from financial accumulation. Separating the layers makes each easier to reason about and test.

**Alternative considered:** A single `BudgetCalculator` with private date helpers. Rejected because the date math is complex enough (especially biweekly) to warrant its own focused test suite, and future features (date-range filtering, period labels in UI) will need period math without financial context.

### 2. Biweekly anchor: most recent week-start day at or before budget creation

**Decision:** For biweekly periods, the anchor that determines cycle alignment is computed as: the most recent occurrence of the user's configured week-start day (`Weekday`) at or before the budget's `createdAt` date.

**How it works:**
- Given `createdAt = Wednesday April 15` and `weekStart = Sunday`, the anchor is `Sunday April 12`.
- Biweekly period boundaries fall every 14 days from that anchor.
- The anchor is deterministic from existing stored data (`createdAt` + `weekStart`) — no new persisted field needed.

**Why this approach:** It aligns biweekly periods with the user's mental model of weeks (starting on their configured day) and anchors to a per-budget reference point. No schema change required.

**Alternative considered:** A fixed global epoch (e.g., Jan 1, 2024). Rejected because different budgets created at different times would share the same biweekly cadence, which could feel arbitrary. A dedicated stored `biweeklyAnchorDate` field was also considered but rejected — it adds schema complexity for something derivable from existing data.

**Risk:** Changing the `weekStartDay` in App Settings shifts the biweekly anchor for all budgets. This is acceptable: the PRD (F-5.01) acknowledges cascading effects and requires a confirmation dialog. The period boundaries will realign naturally.

### 3. All parameters are plain values — `Budget` is not a parameter type

**Decision:** `PeriodCalculator` methods take only `Date`, `BudgetPeriod`, `Weekday`, and `Calendar`. `BudgetCalculator` methods take individual scalar values (`allocation: Decimal`, `periodRaw: String` → parsed to `BudgetPeriod`, etc.) plus `[ExpenseItem]` for expense filtering.

**Why:** `Budget` is a SwiftData `@Model` class that cannot be instantiated without a `ModelContext`. Passing individual values keeps the calculator testable with zero SwiftData setup.

**Exception:** `BudgetCalculator` methods accept `[ExpenseItem]` directly. While `ExpenseItem` is also an `@Model`, the caller (a ViewModel) already has the array from a `@Query`. The calculator only reads `.amount` and `.date` — both plain value types. This pragmatic compromise avoids introducing a separate value-type mirror of `ExpenseItem` for negligible purity gain. Tests will use the existing in-memory `TestModelContainer`.

**Alternative considered:** Accepting `Budget` directly and testing with in-memory containers. Rejected for `PeriodCalculator` (genuinely no need for any model), accepted as pragmatic for expense arrays in `BudgetCalculator`.

### 4. Structured result types

**Decision:** Functions that produce values the caller needs to persist return dedicated result structs:

- `CarryOverRollResult` — `amount: Decimal` + `lastProcessedDate: Date`
- `ResetCheckResult` — `shouldReset: Bool` + `newResetDate: Date?`

**Why:** The caller needs both the computed value and the date to stamp back on the model. Returning just a `Decimal` would force the caller to re-derive the processed date, duplicating logic.

### 5. File placement: `Domain/` folder

**Decision:** Place `PeriodCalculator.swift` and `BudgetCalculator.swift` (with result types) in the existing `Domain/` folder alongside `BudgetPeriod.swift`, `ResetCadence.swift`, and `Weekday.swift`.

**Why:** These are domain-logic files with no UI or persistence dependencies — same category as the enums. The `Domain/` folder already exists and is semantically correct. A new `Services/` folder would be justified if we later add stateful services (e.g., a sync coordinator), but for pure stateless calculators, `Domain/` is the right home.

### 6. Carry-over always computed; toggle is display-only

**Decision:** The calculator always computes and rolls carry-over regardless of `isCarryOverEnabled`. The `isCarryOverEnabled` flag is consumed only by the UI layer to suppress display.

**Why:** If carry-over computation were skipped while disabled, toggling it back on after a long off period would require retroactively walking potentially hundreds of period boundaries from a stale `carryOverLastProcessedDate`. Always computing keeps the figure current and makes toggle-on instant. The computational cost of the roll is trivial (arithmetic per period), and the stored fields exist on the model regardless.

**Alternative considered:** Short-circuit roll when disabled (the original plan). Rejected because it trades negligible CPU savings for significant complexity when the user re-enables carry-over.

### 7. `Calendar` injection

**Decision:** Every function that does date math accepts a `Calendar` parameter (no default). The caller provides `Calendar.autoupdatingCurrent` (or a configured calendar) at the call site; tests inject a fixed-timezone calendar for deterministic results.

**Why:** Calendar math with implicit `Calendar.current` produces timezone-dependent results that are difficult to test reproducibly. Explicit injection ensures tests are deterministic regardless of the CI machine's locale.

## Risks / Trade-offs

**[Biweekly anchor shifts when weekStartDay changes]** → Acceptable per F-5.01 (cascading acknowledged). Period boundaries realign; carry-over roll processes from `carryOverLastProcessedDate` forward, so no data is lost — periods between the old and new anchor are still folded correctly.

**[`ExpenseItem` as `@Model` in calculator signatures]** → A purity compromise. If this becomes a testing pain point, introduce a lightweight `ExpenseRecord` value type that `ExpenseItem` can project into. For now, in-memory `ModelContainer` tests are sufficient.

**[Multi-period catch-up performance for long gaps]** → If a user doesn't open the app for months on a daily budget, the roll iterates through hundreds of periods. Each iteration is trivial arithmetic (sum expenses in date range, subtract from allocation), so this is unlikely to be a real performance issue. If profiling shows otherwise, batch the iteration or short-circuit periods with zero expenses. The tech design doc §6 suggests background-context processing for this case as a future optimization.

**[No explicit handling of `Calendar` locale changes mid-computation]** → The calculator uses the injected `Calendar` instance for the entire computation. If the user changes locale while the app is foregrounded, results update on next access. This is standard iOS behavior and consistent with `Calendar.autoupdatingCurrent`.

## Doc alignment

- **Aligned** with `docs/tech-design-doc.md` §5.3, §3.2, §6.
- **Aligned** with `docs/main-prd.md` §6.7 (all carry-over rules).
- **Update needed after implementation**: `docs/tech-design-doc.md` — add service layer documentation.
