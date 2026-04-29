## Context

The app's primary navigation is a `NavigationStack` driven by an `@Observable Router` (`path: [AppRoute]`, `sheet: SheetRoute?`). `RootView` is the sole sheet host and currently renders bare `Text("Add Budget")` / `Text("Edit Budget")` placeholders for the `SheetRoute.addBudget` and `SheetRoute.editBudget(Budget)` cases. The Budgets list (`BudgetsView`) already presents a per-budget Add Expense, the toolbar `+` triggers `router.sheet = .addBudget`, and the in-progress F-2.02 (Budget detail) screen — when shipped — will trigger `router.sheet = .editBudget(budget)`.

Three throwaway exploration mockups live under `Views/_Mockups/AddEditBudget/` (`MockupA_GroupedForm.swift`, `MockupB_CardLayout.swift`, `MockupC_FlowLayout.swift`) plus shared scaffolding (`MockupShared.swift` — defines `DraftBudget` and `CurrencyPickerStub`). The user has chosen **MockupB · Card Layout** as the production direction. Each mockup file's header explicitly states: _"DESIGN EXPLORATION — throwaway. Delete the entire `_Mockups/` folder when done."_

The `Budget` model is fixed (`Models/Budget.swift`): `name`, `allocation: Decimal`, `currencyCode: String`, `period: String` (raw value of `BudgetPeriod`), `sortOrder: Int`, `createdAt: Date`, `lastModified: Date`, `carryOverAmount: Decimal`, `carryOverLastProcessedDate: Date`, `carryOverLastResetDate: Date`, `resetCadence: String` (raw value of `ResetCadence`, defaulting to `.never` while the feature is paused), `isCarryOverEnabled: Bool`. New rows pull `sortOrder` from `Budget.nextSortOrder(for: context)` (see existing usage in `DebugData.seed` and `BudgetsViewTests`). The `BudgetLifecycleService` owns the `carryOver*` write path; this screen does NOT touch those fields directly.

`AppSettings` (`Settings/AppSettings.swift`) exposes `defaultCarryOverEnabled: Bool` (synced via `NSUbiquitousKeyValueStore`); F-2.07 says new budgets default to that value.

`Localizable.xcstrings` is connected via the `PBXFileSystemSynchronizedRootGroup`; new keys are picked up automatically when the app builds — no `project.pbxproj` edits needed (per `docs/tech-design-doc.md` §5.1).

Constraints in play:

- `docs/main-prd.md` §6.7 — **Reset Cadences are PAUSED**. Do not surface them. New budgets keep `Budget.resetCadence == ResetCadence.never.rawValue`.
- `docs/main-prd.md` §6.4 / `docs/tech-design-doc.md` §5.1–§5.2 — Dynamic Type and VoiceOver are baseline. All new strings live in `Localizable.xcstrings` with `comment:`.
- `docs/tech-design-doc.md` §2.1 — "View + Services, ViewModels on demand". Escalation criterion #1 (form draft state not persisted until the user commits) and grey-area trigger ("more than 3 mutable form fields", we have 5) both apply. A ViewModel is appropriate, with the constraint that it does NOT store `ModelContext`; methods needing to write take `(context: ModelContext, ...)` at the call site.
- `docs/tech-design-doc.md` §3 / §4 — schema is fixed; all new writes use the existing `nextSortOrder` → `insert` → `save` pattern; CloudKit last-writer-wins is acceptable.
- `docs/ux-design-brief.md` — "calm, tidy, quietly warm." No exclamation marks. SF Symbols only. The brief explicitly lists "Add/Edit Budget (sheet)" with allocation, period, carry-over toggle, ~~reset cadence~~ — exactly what MockupB shows.
- F-3.04 — currency picker on Add/Edit Budget; all currencies; localized names; catalog stored "outside source code (e.g. YAML or equivalent)". This change interprets "outside source code" as **Foundation-provided** (`Locale.commonISOCurrencyCodes` + `Locale.localizedString(forCurrencyCode:)`) and proposes updating F-3.04's wording accordingly.

## Goals / Non-Goals

**Goals:**

- Replace the `RootView` placeholders for `SheetRoute.addBudget` and `SheetRoute.editBudget(Budget)` with a single, real `AddEditBudgetView` that satisfies F-2.03 acceptance criteria (minus the paused Reset Cadence bullets).
- Implement the screen as a faithful, production-grade adaptation of `MockupB_CardLayout.swift` — same card structure (Name / Allocation / Period / Carry-Over), same 2×2 period-chip grid, same currency-pill button on the Allocation card. Tighten anything the mockup left as a "TODO production:" note (Decimal-aware allocation input, full ISO-4217 currency picker, localized strings).
- Introduce an `@Observable AddEditBudgetViewModel` per `docs/tech-design-doc.md` §2.1, holding **draft state and pure logic only**. The view owns the VM as `@State`; the VM never stores or fetches via `ModelContext`. Save methods take the context at the call site.
- Ship a real, searchable, full-catalog currency picker backed by Foundation (`Locale.commonISOCurrencyCodes` and `Locale.localizedString(forCurrencyCode:)`). Replace `MockupShared.CurrencyPickerStub`'s 10-entry hardcoded list.
- Insert a new `Budget` (with `Budget.nextSortOrder(for:)`) on Add-mode Save; mutate the passed-in `Budget` on Edit-mode Save with field-by-field comparison so `lastModified` is bumped only when at least one field actually changed.
- Localize every user-visible string in `Localizable.xcstrings` with translator `comment:`s. VoiceOver, Dynamic Type, and Dark Mode are first-class.
- Delete the entire `Views/_Mockups/` tree once the production screen lands.

**Non-Goals:**

- **Reset Cadence in any UI** — paused per `docs/main-prd.md` §6.7 and `docs/product-features-planning.md` F-2.03 callout. The `Budget.resetCadence` field is set by `Budget.init` at insert time and is not exposed by this screen.
- **Project-owned currency catalog file** (YAML or equivalent). The Foundation-backed catalog is sufficient and tracks ISO-4217 updates with the OS; no project-side maintenance needed. F-3.04's wording is updated to reflect this.
- **Currency exchange / conversion** — out of scope per `docs/main-prd.md` §6.5 ("not currency exchange conversions").
- **Save error UI** — no other screen surfaces save errors today (`BudgetsView.move(...)` uses `try?`). This screen follows the same pattern. A dedicated error path is a future concern.
- **Per-budget icons / emoji / photo** — F-4.03 / F-4.04 are unrelated future work.
- **Delete Budget UX** — explicitly deferred per the recent `2026-04-26-finish-budgets-screen` scope decision.
- **Bulk currency / period changes** — not part of F-2.03.
- **iPad / Mac split-view layout for the sheet** — the sheet uses the default modal presentation; iPad and Mac inherit standard SwiftUI sheet sizing. No `presentationDetents` customisation.
- **`AppRoute` / `SheetRoute` changes** — the existing `.addBudget` and `.editBudget(Budget)` cases are sufficient. No new cases.
- **Budget detail (F-2.02) entry point** — when F-2.02 lands it will trigger `router.sheet = .editBudget(budget)`; this change makes that sheet present the real screen, but does NOT add the trigger itself (Budget detail is still a placeholder).

## Decisions

### Decision 1: Use an `@Observable AddEditBudgetViewModel` (not view-only `@State`)

**Choice:** Introduce `Views/AddEditBudgetViewModel.swift` as `@Observable final class AddEditBudgetViewModel`, owned by `AddEditBudgetView` as `@State` (the SwiftUI ownership idiom for `@Observable` reference types). The VM holds:

- `var name: String`
- `var allocation: Decimal` (NOT a `String`; see Decision 4)
- `var currencyCode: String`
- `var period: BudgetPeriod`
- `var isCarryOverEnabled: Bool`
- A `mode: Mode` enum (`.add` or `.edit(Budget)`).
- A pure `var canSave: Bool { ... }` computed property.
- A `func save(context: ModelContext)` method that performs the Add or Edit branch.

The VM does NOT hold or capture `ModelContext`, does NOT fetch, and does NOT hold `AppSettings` long-term (it reads `settings.defaultCarryOverEnabled` only inside the Add-mode initialiser; runtime mutations of `AppSettings` after the sheet opens do not propagate into the in-flight draft, by design).

**On the `save(...)` signature.** `docs/tech-design-doc.md` §2.1 says: _"Methods that need to write take `(context: ModelContext, ...)` at the call site (and `AppSettings` similarly when relevant)."_ For our save body, `AppSettings` is **not** relevant — neither the Add-mode insert nor the Edit-mode field-comparison rewrite reads any property of `AppSettings`. (The Add-mode default for `isCarryOverEnabled` is captured at `init` time; by the time `save(...)` runs, it lives in the VM's `isCarryOverEnabled` field as drafted by the user.) Following §2.1's "when relevant" rider, `save` takes only `context: ModelContext`. Currency-display preference (`AppSettings.currencyDisplay`) is a pure view-side concern (Decision 15) and never reaches the persistence layer at all.

**Alternatives considered:**

- **`@State` properties on the view (no VM)** — what MockupB does. Rejected because: (a) §2.1 escalation criterion #1 explicitly applies (form draft state not persisted until commit); (b) §2.1 grey-area trigger "more than 3 mutable form fields" applies (we have 5); (c) testing the `save(...)` orchestration without a host SwiftUI view is much easier with a VM than with `@State`-only logic.
- **Pass each field as a separate parameter to a free function** — rejected because state still has to live somewhere reactive, and packaging it in a VM gives one focused unit-test target. The VM also gives a natural place for the Edit-mode field-comparison logic.
- **Persist a draft `DraftBudget` value type (mirroring the mockup's helper)** — rejected because the production screen edits / inserts a real `Budget`, not a separate value type. A second type would only add translation overhead between draft and model.

**Rationale:** §2.1 is explicit about when to escalate. Both criterion #1 and a grey-area trigger apply; not escalating would leave save-orchestration logic embedded in the view body where it cannot be unit tested.

### Decision 2: Add and Edit modes share one screen, distinguished by the VM initialiser

**Choice:** `AddEditBudgetViewModel.Mode` is one of:

- `.add` — the Add path. The VM is created via `init(settings: AppSettings)` and seeds defaults: `name = "Budget"`, `allocation = 10`, `currencyCode = Locale.current.currency?.identifier ?? "USD"`, `period = .daily`, `isCarryOverEnabled = settings.defaultCarryOverEnabled`. These defaults match `Budget.init` (allocation = 10, currency from locale, period = `.daily`) and F-2.07 (carry-over default from `AppSettings`).
- `.edit(Budget)` — the Edit path. The VM is created via `init(editing: Budget)` and seeds each field from the existing budget: `name = budget.name`, `allocation = budget.allocation`, `currencyCode = budget.currencyCode`, `period = BudgetPeriod(rawValue: budget.period) ?? .daily`, `isCarryOverEnabled = budget.isCarryOverEnabled`. The VM stores a reference to the `Budget` so `save(...)` can mutate it.

The view chooses navigation title based on mode: `"New Budget"` for `.add`, `"Edit Budget"` for `.edit`. The Save button label stays `"Save"` (matches MockupB; `MockupC`'s "Add Budget" / "Save Changes" wording is intentionally not adopted to keep the toolbar item compact).

**Alternatives considered:**

- **Two separate views (`AddBudgetView`, `EditBudgetView`)** — rejected because the form, validation, and persistence logic are 95% identical. Two views would duplicate the entire layout. F-2.03's first acceptance criterion says explicitly: _"Same screen used to create and edit."_
- **Pass an optional `Budget?` directly into the view** — rejected because the view has to fork on `.some` vs `.none` everywhere; a `Mode` enum is type-safer and the optional version pollutes call sites.

**Rationale:** F-2.03 mandates a single screen. The `Mode` enum is the simplest internal representation of Add vs Edit and keeps the seeding and saving logic in the VM rather than the view.

### Decision 3: Carry the period seeding from the existing `Budget` raw value safely

**Choice:** When seeding from an existing `Budget`, decode the period via `BudgetPeriod(rawValue: budget.period) ?? .daily`. This mirrors `BudgetRowView`'s pattern (`BudgetsView.swift:160`).

**Alternatives considered:**

- **Force-unwrap (`!`)** — rejected because a stale CloudKit record could carry an unknown `period` raw value (e.g., from a future schema version); falling back to `.daily` is safer than crashing.
- **Add a `BudgetPeriod` accessor to `Budget`** — out of scope; matches the existing pattern instead.

**Rationale:** Defensive decoding mirrors existing app code and prevents a crash from a malformed CloudKit record.

### Decision 4: Allocation is edited as `Decimal` via `TextField(value: $vm.allocation, format: ...)`, not as a `String`

**Choice:** The Allocation card binds the field with a `Decimal`-typed `TextField`:

```
TextField(
    "0",
    value: $viewModel.allocation,
    format: .number.precision(.fractionLength(0...2))
)
.keyboardType(.decimalPad)
```

The MockupB pattern of holding `allocationText: String` and re-parsing on Save was explicitly tagged `// TODO production: Use Decimal.FormatStyle with locale-aware keyboard input.` We honour that TODO at the source of truth — the VM — by keeping `allocation: Decimal` directly. SwiftUI handles locale-aware decimal input (`,` vs `.`) for free with `.number` format styles.

**Alternatives considered:**

- **Keep `allocationText: String` + manual parsing** — rejected because it inherits the mockup's TODO debt: `Decimal(string:)` does not handle locale separators, the placeholder/format defaults are inconsistent across locales, and the VM ends up with two sources of truth for the amount.
- **Currency-formatted input (`.currency(code: vm.currencyCode)`)** — rejected because the user is entering a number, and the currency code is shown adjacent to the field as a separate pill (per MockupB). Mixing a currency-formatted input with a separate currency pill produces a redundant currency symbol.
- **Custom `Decimal` parser** — rejected; SwiftUI provides the locale-aware path.

**Rationale:** `Decimal`-typed `TextField` with `.number` format style is the canonical SwiftUI path for locale-aware numeric entry; matches `docs/tech-design-doc.md` §1.1 ("monetary values stored as `Decimal`, never floating-point") at the input layer too.

#### Edge cases for `canSave`

`canSave` SHALL evaluate to `true` only when:

- `name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false`, AND
- `allocation > 0` (not `>= 0`; a zero allocation is a degenerate "budget that allows nothing", indistinguishable from forgetting to enter a value).

Negative allocations are not reachable from the `.decimalPad` keyboard, but the `> 0` check is the canonical guard regardless.

### Decision 5: Currency picker — Foundation-backed catalog, presented as an inner sheet

**Choice:** Implement `Views/CurrencyPickerView.swift` as a `View` shown via `.sheet(isPresented:)` from `AddEditBudgetView`. The picker:

- Sources its codes from `Locale.commonISOCurrencyCodes` (returns ~155 ISO-4217 codes maintained by Apple).
- Renders each row with: code on the left, localized name on the right (`Locale.current.localizedString(forCurrencyCode: code)` — falls back to the code itself if the localized name is `nil`).
- Provides a `.searchable(text:)` field that filters by **code (case-insensitive prefix match)** OR **localized name (case-insensitive `localizedCaseInsensitiveContains`)**.
- Sorts results by code ascending (stable, deterministic for tests).
- Has a leading `Cancel` toolbar item that dismisses without committing; tapping a row commits the selection and dismisses the picker.
- Has a checkmark adornment on the currently-selected row.

**Alternatives considered:**

- **Project-owned YAML catalog** — rejected per Goals/Non-Goals: F-3.04's "stored outside source code" goal is met by Foundation; we drop a maintenance burden. F-3.04 wording is updated.
- **`Locale.Currency.isoCurrencies` (richer struct catalog)** — `Locale.Currency` exists in newer SDKs but `commonISOCurrencyCodes` is the canonical SwiftUI / Foundation path with broader compatibility and tighter integration with `Locale.localizedString(forCurrencyCode:)`. We use the simpler API.
- **Inline navigation push instead of a sheet-on-sheet** — rejected because the parent presentation is itself a sheet; pushing onto the parent's `NavigationStack` would not be available, and a separate `NavigationStack` inside the picker matches what MockupB's `CurrencyPickerStub` already does (and what HIG recommends for sub-pickers inside modal forms).
- **Inline picker (no sheet, list embedded under the Allocation card)** — rejected; would dominate the form's visual hierarchy and break the card layout.

**Rationale:** Foundation owns the canonical ISO-4217 list; the maintenance burden of a project-owned YAML is unjustified while there's no divergence from Foundation. Sheet-on-sheet is the standard iOS pattern for sub-pickers and matches the mockup's affordance.

#### Sheet-on-sheet detail

The currency picker is presented from inside `AddEditBudgetView`, which is itself a sheet hosted by `RootView`. SwiftUI supports sheet-on-sheet on iOS 26 cleanly; both the parent and child sheets share the same `Router` environment but neither writes to it. The currency picker's dismissal is local (`@Environment(\.dismiss)`).

### Decision 6: Period chips — adopt MockupB's 2×2 grid; future 5+ option is not a blocker

**Choice:** Render the four `BudgetPeriod` cases (`.daily`, `.weekly`, `.biweekly`, `.monthly`) as a `LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8)`. Each chip is a `Button` with the `RoundedRectangle` background from MockupB. Selection bumps the chip's font weight to `.semibold`, fills the background with `Color.accentColor`, and sets foreground to white.

The chip button SHALL declare `.accessibilityAddTraits(.isSelected)` when selected, which is the standard VoiceOver pattern for option lists. The accessibility label is `"<Period> period"` (e.g., `"Daily period"`) sourced from a localization key parameterised by `BudgetPeriod.listLabel`.

Long-term: if a fifth period is ever added (the mockup's open question), the layout will break visually (odd-row chip alone). That is a separate change. The 2×2 grid is correct for the four periods we have today.

**Alternatives considered:**

- **Segmented `Picker`** — rejected per MockupA's open-question note: "Biweekly" truncates on iPhone SE at default text size; the segmented control is also brittle for Dynamic Type at large sizes.
- **Menu picker (`.pickerStyle(.menu)`)** — rejected; hides the choices behind a tap and trades expressiveness for compactness, which is the wrong trade for a low-frequency setup screen.
- **Chip `Picker`** with iOS 26's `.palette` style — feasible but adds platform coupling and matches the mockup's behaviour less precisely. The hand-rolled chips give us full control over the selected/unselected style.

**Rationale:** The 2×2 grid resolves the truncation problem MockupA flagged, gives every chip full text room at all Dynamic Type sizes, and matches the visual weight the UX brief calls for ("budgets read like a well-organized accounting ledger, not a dashboard"). VoiceOver's `.isSelected` trait is the canonical option-list pattern.

### Decision 7: Carry-over card layout

**Choice:** A `GroupBox` titled `"Carry-Over"` containing:

- A `Toggle("Carry-Over", isOn: $viewModel.isCarryOverEnabled)` with `.tint(.accentColor)` and an accessibility hint `"When on, unspent or overspent amounts carry forward across periods"`.
- A short caption beneath the toggle: `"Accumulates unspent or overspent amounts over time."` — always visible (whether the toggle is on or off), per MockupB. (MockupA's variable footer is rejected; the caption is informative even in the off state because the accumulation continues internally per PRD §6.7.)

The toggle does NOT trigger any save — the carry-over flag is committed only when the user taps Save in the toolbar.

**Alternatives considered:**

- **Animate the caption out when off** — rejected; the caption explains an invariant of the feature ("accumulates over time") that holds regardless of the toggle state. Hiding it would be misleading.
- **Add a "Reset carry-over" button on this screen** — rejected; per F-2.02, the carry-over reset control lives on the **Budget screen** (Budget detail), not the Add/Edit Budget screen.

**Rationale:** Aligns with PRD §6.7's explicit guarantee: when carry-over is off, the underlying figure is _still maintained_ internally so re-enabling it produces an immediately correct value. The caption keeps the invariant visible.

### Decision 8: Save semantics and persistence flow

**Choice:** `func save(context: ModelContext)` performs:

#### Add mode (`.add`)

1. Construct a `Budget` via `Budget(name:, allocation:, currencyCode:, period:, isCarryOverEnabled:)` — passing exactly the draft fields. The `resetCadence` defaults to `.never` per the existing `Budget.init` (paused).
2. Set `budget.sortOrder = (try? Budget.nextSortOrder(for: context)) ?? 0`. The `try?` mirrors `DebugData.seed`'s pattern; a fetch failure is recoverable (we just put the new row at sortOrder 0 in the worst case).
3. `context.insert(budget)`.
4. `try? context.save()`.

#### Edit mode (`.edit(let budget)`)

For each editable field, compare draft to current; only mutate when different. On any mutation, set `budget.lastModified = Date()` once at the end. Then `try? context.save()`.

```
var didChange = false
if budget.name != name { budget.name = name; didChange = true }
if budget.allocation != allocation { budget.allocation = allocation; didChange = true }
if budget.currencyCode != currencyCode { budget.currencyCode = currencyCode; didChange = true }
if budget.period != period.rawValue { budget.period = period.rawValue; didChange = true }
if budget.isCarryOverEnabled != isCarryOverEnabled {
    budget.isCarryOverEnabled = isCarryOverEnabled
    didChange = true
}
if didChange {
    budget.lastModified = Date()
    try? context.save()
}
```

The `try?` matches `BudgetsView.move(...)`. No save error UI is presented (out of scope; matches the rest of the app today).

#### Cancel

The view dismisses via `@Environment(\.dismiss)`. The VM is deallocated. No fields on any `Budget` are mutated.

**Alternatives considered:**

- **Always rewrite all fields on Edit-mode Save** — rejected; would bump `lastModified` on every Save even if the user didn't actually change anything. Same rationale used in `BudgetsView.move(...)`'s "skip rows whose `sortOrder` value is unchanged" decision.
- **Throwing `save(...)` with an error sheet** — out of scope; not a pattern this app surfaces today.
- **Push to a background `ModelContext` for the write** — unnecessary for a single-row insert/update at the scale this app expects (`docs/tech-design-doc.md` §6 only mentions backgrounding for multi-period rolls).

**Rationale:** Field-level comparison gives clean `lastModified` semantics consistent with the rest of the app. The `try?` save matches the project pattern. Minimal risk for a synchronous, small write.

### Decision 9: View structure mirrors MockupB's card composition (no further redesign)

**Choice:** `AddEditBudgetView.body` is a `NavigationStack` containing a `ScrollView` of four `GroupBox` cards (Name, Allocation, Period, Carry-Over) with `.appBackground()`, the `Cancel` / `Save` toolbar, and a `.sheet(isPresented:)` for the currency picker. We retain MockupB's spacing (`VStack(spacing: 16)`, horizontal padding, `top 8` / `bottom 32` insets). The `GroupBox.backgroundStyle(Color("CellBackground"))` line is preserved on each card.

**Alternatives considered:**

- **Variant A's `Form` style** — rejected; the user explicitly chose MockupB.
- **Variant C's amount-hero with pinned Save** — rejected; same reason.
- **Custom card backgrounds without `GroupBox`** — rejected; `GroupBox` provides automatic Dynamic Type behaviour and label hierarchy that we'd otherwise reimplement.

**Rationale:** The user's design choice is explicit. The mockup is already very close to production; the work is mostly about wiring real state and hardening for production (Decimal allocation, real currency picker, localized strings).

#### Card titles use `sectionLabel(_:)`

Per MockupB, the `GroupBox` label uses `.subheadline` and `.foregroundStyle(.secondary)`. We retain this. The label texts ("Name", "Allocation", "Period", "Carry-Over") are localized.

### Decision 10: Localization — every new user-visible string in `Localizable.xcstrings`

**Choice:** All new strings use `String(localized: "key", defaultValue: "...", comment: "translator context")` (or `Text(LocalizedStringKey)` where keys are stable enough). Keys follow the existing dotted convention used elsewhere in the file (e.g., `addEditBudget.title.add`, `addEditBudget.section.name`, `addEditBudget.action.save`).

Concrete keys (and English defaults) introduced by this change:

- `addEditBudget.title.add` → `"New Budget"` — sheet navigation title (Add mode).
- `addEditBudget.title.edit` → `"Edit Budget"` — sheet navigation title (Edit mode).
- `addEditBudget.action.cancel` → `"Cancel"` — leading toolbar button (and currency-picker leading toolbar).
- `addEditBudget.action.save` → `"Save"` — trailing toolbar button.
- `addEditBudget.section.name` → `"Name"` — Name card label.
- `addEditBudget.field.name.placeholder` → `"Budget"` — Name `TextField` placeholder.
- `addEditBudget.field.name.accessibilityLabel` → `"Budget name"`.
- `addEditBudget.section.allocation` → `"Allocation"` — Allocation card label.
- `addEditBudget.field.allocation.placeholder` → `"0"` — Allocation `TextField` placeholder.
- `addEditBudget.field.allocation.accessibilityLabel` → `"Allocation amount, %@ %@"` — VoiceOver label; `%1$@` is the formatted amount, `%2$@` is the currency code. _(See "Localized formatted-string arguments" note below.)_
- `addEditBudget.field.currency.accessibilityLabel` → `"Currency, %@"` — VoiceOver label for the currency pill.
- `addEditBudget.field.currency.accessibilityHint` → `"Opens currency picker"`.
- `addEditBudget.section.period` → `"Period"` — Period card label.
- `addEditBudget.chip.period.accessibilityLabel` → `"%@ period"` — VoiceOver label per chip; `%@` is `BudgetPeriod.listLabel`.
- `addEditBudget.section.carryOver` → `"Carry-Over"` — Carry-Over card label and toggle title (used in two places).
- `addEditBudget.toggle.carryOver.accessibilityHint` → `"When on, unspent or overspent amounts carry forward across periods"`.
- `addEditBudget.note.carryOver` → `"Accumulates unspent or overspent amounts over time."`.
- `currencyPicker.navigationTitle` → `"Currency"` — currency-picker navigation title.
- `currencyPicker.search.prompt` → `"Search currencies"` — `searchable` prompt text.
- `currencyPicker.row.accessibilityLabel` → `"%@, %@"` — VoiceOver label per row; `%1$@` is the code, `%2$@` is the localized name.
- `currencyPicker.row.selected.accessibilityValue` → `"selected"` — appended via `.accessibilityValue` on the currently-selected row.

#### Localized formatted-string arguments

Where a string takes positional arguments (e.g., `"Allocation amount, %@ %@"`), the call site uses `String(localized: "key", defaultValue: "..., \(amount) \(code)", comment: "...")` which the catalog tooling will lift into a `%@` form per Apple's String Catalog conventions. The catalog already contains a similar key `"Allocation amount, %@ %@"` left over from the mockup; we replace the legacy entry with the namespaced `addEditBudget.field.allocation.accessibilityLabel` key.

#### Reuse of existing keys

Existing toolbar-and-row keys in the catalog (`toolbar.addBudget.accessibilityLabel`, `budget.row.accessibilityLabel`, etc.) are unrelated to the sheet's contents and are NOT reused here. The sheet's keys are namespaced under `addEditBudget.*` to avoid bleed into list-screen contexts. The currency picker uses its own `currencyPicker.*` namespace.

#### Mockup-residual keys to remove

The mockup files declared local strings like `"Add Budget"`, `"Edit Budget"`, `"Cancel"`, `"Save"`, `"Currency"` directly in `Text(...)`. The xcstrings catalog auto-extracted these as English-only entries. After deleting `_Mockups/`, the catalog tool will mark those auto-extracted entries as **stale** on the next build; we may either let them be garbage-collected or hand-prune them. The decision is a trivial post-implementation cleanup (covered by `tasks.md` §4).

**Alternatives considered:**

- **`LocalizedStringKey`-only (no `String(localized:)`)** — rejected because some labels need to be composed inside accessibility strings (e.g., `accessibilityLabel(...)` takes a `String`, not `Text`). A mix is consistent with the rest of the codebase.
- **Reuse `"Budget"` as both placeholder and section title** — rejected; section-title context differs from placeholder context and translators benefit from per-context keys.

**Rationale:** Matches the pattern already established in `BudgetsView.swift` and follows §5.1 verbatim. Namespacing under `addEditBudget.*` and `currencyPicker.*` keeps each feature's strings discoverable in the catalog UI.

### Decision 11: Delete the entire `_Mockups/` tree as part of this change

**Choice:** The change includes deleting:

- `simple-recurring-budgets/Views/_Mockups/AddEditBudget/MockupA_GroupedForm.swift`
- `simple-recurring-budgets/Views/_Mockups/AddEditBudget/MockupB_CardLayout.swift`
- `simple-recurring-budgets/Views/_Mockups/AddEditBudget/MockupC_FlowLayout.swift`
- `simple-recurring-budgets/Views/_Mockups/AddEditBudget/MockupShared.swift`
- The now-empty `Views/_Mockups/AddEditBudget/` and `Views/_Mockups/` directories.

The `Resources/Localizable.xcstrings` entries that were auto-extracted from the mockup files (`"Add Budget"`, `"%@ period"`, `"Allocation amount, %@ %@"`, etc.) become unreferenced; we let the catalog tool surface them as stale and either remove them in this change or leave them for the next localization pass. The decision is captured in tasks.md §4.

The mockups depend on `BudgetPeriod` and `MockupShared.DraftBudget`; deleting `MockupShared` is a hard cut — `DraftBudget` was throwaway helper state and is not used anywhere outside the mockups. The mockup-only `BudgetPeriod.mockPerLabel` extension lives in `MockupShared` and goes with it (no other consumer).

**Alternatives considered:**

- **Keep mockups in a `#if DEBUG` block** — rejected because the mockups are duplicate UIs that will rot. The user's request is explicit ("delete all the mocks ... and the `_Mockups` folder when we're done with them").
- **Keep `MockupShared.DraftBudget` as a reusable test helper** — rejected; the production VM is the source of truth for the form draft. Tests build VMs directly.

**Rationale:** Honours the file-header instruction and the user's explicit ask; removes a maintenance liability.

### Decision 12: Wire Add and Edit branches through `RootView`

**Choice:** `RootView`'s `.sheet(item: $router.sheet) { route in switch route { ... } }` block changes:

- `case .addBudget:` → `AddEditBudgetView(viewModel: AddEditBudgetViewModel(settings: settings))` — read `settings` from `@Environment(AppSettings.self)`.
- `case .editBudget(let budget):` → `AddEditBudgetView(viewModel: AddEditBudgetViewModel(editing: budget))`.

`AddEditBudgetView` takes the VM in its initialiser and stores it as `@State`. The `context` environment value is read inside the view's `body` and passed to `viewModel.save(context: context)` at the call site (per §2.1 VM rules: VM does NOT hold it). `AppSettings` is read by the view via `@Environment(AppSettings.self)` and consumed for the Allocation field's accessibility-label formatting (Decision 15); it is NOT passed to `save`.

The other `RootView` sheet arms are NOT touched by this change. As of the prior `2026-04-28-settings-screen` change, `case .settings:` already routes to the real `SettingsView()`. The `case .addExpense:` and `case .viewExpense:` arms remain placeholder `Text(...)` views until F-2.04 ships. The merged commit also added a `SyncStatus` `@Observable` env value injected at the app entry point (`simple_recurring_budgetsApp`) and mirrored in the `RootView` `#Preview`; our new previews for the Add/Edit Budget sheet (Decision 13 and tasks.md §3.8 / §4.5) MUST inject the same env values (`Router`, `AppSettings`, `SyncStatus`) so the previews match the production injection surface, even though the Add/Edit Budget sheet itself does not consume `SyncStatus`.

Sketch:

```swift
case .addBudget:
    AddEditBudgetView(viewModel: AddEditBudgetViewModel(settings: settings))
case .editBudget(let budget):
    AddEditBudgetView(viewModel: AddEditBudgetViewModel(editing: budget))
```

**Alternatives considered:**

- **Have `AddEditBudgetView` infer the mode from a `Budget?` parameter** — rejected; the explicit `Mode` enum on the VM is clearer at the call site.
- **Construct the VM inside `AddEditBudgetView.init(mode:)` rather than at the route call site** — viable, but the call site needs `settings` (which lives on `RootView`'s environment). Passing the constructed VM up keeps the construction in one place where `settings` is already available without further plumbing.

**Rationale:** Keeps the route-to-screen wiring explicit and free of `Environment`-only lookups deep in view hierarchy.

### Decision 13: Tests — Swift Testing on the VM, view-level smoke tests via previews

**Choice:** All deterministic logic lives in `AddEditBudgetViewModel`; tests target it directly with Swift Testing (`@Test`, `#expect`) in `simple-recurring-budgetsTests/Views/AddEditBudgetViewModelTests.swift`. An in-memory `ModelContainer` is created per test via the existing `TestModelContainer` helper.

Coverage:

1. Add-mode defaults match the documented values (allocation 10, locale currency or USD, period .daily, carry-over from settings, name "Budget").
2. Edit-mode seeding mirrors the passed-in `Budget` for every editable field.
3. `canSave` returns `false` when name is empty or whitespace-only, when allocation is zero, and when allocation is negative; returns `true` otherwise.
4. Add-mode `save(...)` inserts exactly one new `Budget` with the drafted fields, with `sortOrder` equal to the next available value (0 in an empty store, `max + 1` otherwise).
5. Edit-mode `save(...)` mutates only the fields that differ; rows whose value did not change SHALL retain their old `lastModified`. When at least one field changes, `lastModified` is updated to a `Date()` that is `> originalLastModified`. (The test fixes a "before" date, mutates, asserts ≥ "before"; we don't pin to wall-clock equality.)
6. Edit-mode `save(...)` with no changes does NOT call `context.save()` (verified indirectly: `lastModified` remains the original value).
7. Cancel writes nothing — verified by constructing a VM, mutating fields, **not** calling `save(...)`, and asserting the original `Budget` rows in the store are unchanged.

Currency picker tests live in `simple-recurring-budgetsTests/Views/CurrencyPickerTests.swift` and target the picker's pure helper(s):

1. The catalog source returns `Locale.commonISOCurrencyCodes` sorted ascending and de-duplicated.
2. The display-name lookup falls back to the code when `Locale.localizedString(forCurrencyCode:)` returns `nil`.
3. The search filter matches by code prefix (case-insensitive) AND by localized-name `localizedCaseInsensitiveContains`.

**Alternatives considered:**

- **UI snapshot tests** — out of scope per `docs/tech-design-doc.md` §5.3; we rely on `#Preview`s for visual smoke checks (light, dark, xxxLarge, empty/edit modes).
- **Test the full sheet via SwiftUI's `inspect` / hosting controllers** — brittle; the VM contract is the unit-test target.

**Rationale:** Aligns with `docs/tech-design-doc.md` §5.3 (Swift Testing, in-memory `ModelContainer`, business logic in pure services / VMs). Every requirement scenario in the spec maps to at least one VM test.

### Decision 14: Doc updates required by this change

**Choice:** Two `docs/*.md` files SHALL be updated **in this change** (not deferred):

1. `docs/product-features-planning.md` —
    - **F-2.03 (Add/Edit Budget screen)**: flip `**Status:** Open` → `**Status:** Implemented (excluding paused Reset Cadences)`. Leave the existing PAUSED note unchanged. Add a brief implementation note pointing at this change name and the Foundation-backed currency catalog.
    - **F-3.04 (Internationalization of currency)**: relax the third acceptance criterion ("Currency catalog (codes, symbols, localized names) is stored outside source code (e.g. YAML or equivalent).") to: _"Currency catalog (codes, symbols, localized names) is sourced from outside our application source — either from Foundation's system catalog (`Locale.commonISOCurrencyCodes` plus `Locale.localizedString(forCurrencyCode:)`) or from a project-owned data file (e.g. YAML) when the app needs to diverge from the system catalog. The Add/Edit Budget screen ships the system-catalog path."_ Mark the picker-on-Add/Edit-Budget criterion and the localized-name criterion as implemented for this screen.
2. `docs/tech-design-doc.md` — **no edit expected.** None of the architectural sections (§2.1, §3, §4, §5) materially change. If implementation surfaces a genuinely new architectural rule it should be captured then; otherwise no version-history bump.

`docs/main-prd.md` and `docs/ux-design-brief.md` are unchanged.

**Alternatives considered:**

- **Defer F-2.03 status flip until the verify step** — rejected; the proposal already established the flip is the right doc state, and pushing it to verify introduces drift between the change and the docs at archive time.
- **Restate F-3.04 entirely** — rejected; relaxing one criterion is sufficient. Other F-3.04 criteria (per-budget currency on Add/Edit Budget; locale-aware formatting; localized currency names in the picker) are already accurate.

**Rationale:** Matches the workspace's `Doc maintenance protocol` ("update the corresponding `docs/` file(s) in the same effort") and the OpenSpec config's `apply` rule ("when work changes behavior covered by `docs/`, either update docs in-repo as part of tasks or leave an explicit follow-up task; do not treat the change as complete with drift").

### Decision 15: Respect `AppSettings.currencyDisplay` in the Allocation accessibility label

**Choice:** The Allocation card's `TextField` displays the user's typed numeric value as-is (no currency formatting on the visible glyphs — that is intentional; the user is entering a number while the currency code lives in the adjacent pill). However, the field's **VoiceOver accessibility label** announces the value as a formatted monetary amount (e.g. `"$25.00"`). That formatted announcement SHALL be produced by the canonical `Decimal.formatted(currencyCode:display:locale:)` overload (added in commit `a6b2e46`) with `display: settings.currencyDisplay`, where `settings` is read from `@Environment(AppSettings.self)`.

Concretely:

```swift
let formattedAllocation = viewModel.allocation
    .formatted(currencyCode: viewModel.currencyCode, display: settings.currencyDisplay)
// Used inside `String(localized: "addEditBudget.field.allocation.accessibilityLabel", ...)`
```

The view SHALL read `AppSettings` via `@Environment(AppSettings.self)`. The accessibility label is recomputed naturally by SwiftUI on changes to `viewModel.allocation`, `viewModel.currencyCode`, or `settings.currencyDisplay` (the latter via `@Observable`'s tracking).

This matches the pattern established by `BudgetsView.swift` after the merged commit (`Text(remaining.formatted(currencyCode: budget.currencyCode, display: settings.currencyDisplay))`) and by `CarryOverChip.swift` (`display: display` plumbed through).

**Why only the accessibility label, not the visible field:** The visible Allocation field is a `TextField(value: $viewModel.allocation, format: .number...)` — a numeric editor, not a formatted display. Users want to type `25.50`, not `$25.50`. The currency code is shown in the adjacent pill. The accessibility label is the only place where a fully-formatted monetary string is announced, and that string SHOULD honour the user's app-wide preference.

**Other touchpoints in this screen:**

- The currency pill on the Allocation card displays only the raw ISO code (e.g. `"USD"`) — unaffected by `currencyDisplay` (the pill exists to switch the code itself).
- The currency picker rows show `code + localized name`, not formatted amounts — unaffected.
- The card titles, period chips, name field, carry-over toggle, and caption do not render any monetary amount — unaffected.

So this is a single-touchpoint integration: read `settings.currencyDisplay`, pass it to the canonical formatter, done.

**Alternatives considered:**

- **Hard-code `display: .symbol` everywhere on this sheet** — rejected; would break the app-wide preference contract documented in `app-settings`'s `currencyDisplay setting` requirement and demonstrated in `BudgetsView` / `CarryOverChip`.
- **Plumb `currencyDisplay` through the VM as a stored field** — rejected; the preference is a view-side concern, the VM has no business knowing about it, and the §2.1 rule "VM holds draft state and pure logic only" applies. Reading `@Environment(AppSettings.self)` directly in the view is the right shape.
- **Format the visible Allocation `TextField` with currency** (via `.currency(code:)` format style) — rejected per Decision 4: would produce a redundant currency symbol next to the currency pill, and the user is in a numeric editing context.

**Rationale:** Mirrors the precedent set by the existing money-rendering call sites in this codebase (`BudgetsView`, `CarryOverChip`) and keeps the new screen aligned with the `app-settings`-spec requirement that `currencyDisplay` apply app-wide. No new VM coupling.

## Risks / Trade-offs

- **[Foundation currency catalog drifts from a future product need]** → If the app later wants currencies that Apple does not list (e.g., crypto, deprecated codes the user wants to retain), the Foundation catalog won't suffice. Mitigation: F-3.04's relaxed wording leaves the door open for a project-owned YAML in a future change. No code is wasted — the picker's data source is a small protocol/seam.
- **[Sheet-on-sheet stacking on iPad/Mac may feel cluttered]** → On larger sizes the parent sheet may already feel modal-heavy; presenting the currency picker on top of it adds another modal surface. Mitigation: standard sheet sizing on iPad/Mac handles two-deep modals fine in iOS 26. If TestFlight reveals friction, switch the currency picker to a `NavigationStack` push within the parent sheet (one-line change, isolated).
- **[Decimal-typed `TextField` UX with empty input]** → A `Decimal`-bound `TextField` shows `0` (or the formatted zero) when empty; typing then clears and replaces. For most users this is fine; for muscle-memory iOS form users it can feel slightly different from a `String`-bound text field. Mitigation: the placeholder text `"0"` and the `.decimalPad` keyboard make the affordance unambiguous; the standard SwiftUI behaviour is what we want.
- **[Edit-mode field comparison on `Decimal` is value-equal, not representation-equal]** → `Decimal` value equality (`10` vs `10.0`) treats them as equal even if the user retyped the number. Mitigation: that is the correct behaviour — no real change → no `lastModified` bump. Aligns with the goal.
- **[Stale auto-extracted xcstrings entries from deleted mockups]** → The catalog will retain auto-extracted entries from `_Mockups/` until they are explicitly removed. Mitigation: tasks.md §4 includes a step to verify the catalog is consistent post-delete; a hand-prune of stale entries is acceptable cleanup.
- **[`AppSettings.defaultCarryOverEnabled` change after the sheet is already open]** → If the user opens Add Budget, then somehow toggles the global default in another part of the system before saving (impossible from this UI today, but possible across CloudKit-synced devices), the in-flight draft retains the value at sheet-open time. Mitigation: documented as intentional in Decision 1; the user can flip the per-budget toggle on the Add screen if they care.
- **[Concurrent edit of the same `Budget` from two devices via CloudKit]** → Standard last-writer-wins semantics. Mitigation: acceptable per `docs/tech-design-doc.md` §4.4 — single-user, personal-device sync.
- **[Save errors from `try? context.save()` are swallowed]** → No user-visible feedback when saving fails (e.g., disk full). Mitigation: matches existing app pattern (`BudgetsView.move(...)`); a save-error UX is a future cross-cutting concern not scoped here.
- **[VoiceOver-only divergence between the visible Allocation field and its accessibility label]** → The visible `TextField` shows a raw number (`25.50`); the announced label includes a currency-formatted monetary string (`"$25.50"` or `"USD 25.50"` depending on `settings.currencyDisplay`). Sighted users see `25.50`; VoiceOver users hear `"$25.50"`. Mitigation: this is by design (Decision 4 + Decision 15) and matches user expectation — VoiceOver typically announces semantically-rich content. Reviewers should confirm the announcement is unambiguous in TestFlight; if it ever feels noisy, the label can be simplified to just the number plus the code without breaking any spec scenario other than the explicit "label respects currencyDisplay" scenario.
- **[`SyncStatus` env value not present in older preview helpers]** → The merged commit added a new `@Observable SyncStatus` env value injected at the app entry point and mirrored in `RootView`'s `#Preview`. Any new preview blocks we add for the Add/Edit Budget sheet routed through `RootView` MUST inject `SyncStatus` to compile, even though the sheet itself does not consume it. Mitigation: tasks.md §3.8 / §4.5 explicitly call out the env injection list; previews that render `AddEditBudgetView` directly (not through `RootView`) do not need `SyncStatus`.

## Migration Plan

1. **Land this change as a single PR.**
    - `Views/AddEditBudgetView.swift`, `Views/AddEditBudgetViewModel.swift`, `Views/CurrencyPickerView.swift` are new files.
    - `Views/RootView.swift` switches `.addBudget` and `.editBudget(Budget)` from placeholders to the real view.
    - `Resources/Localizable.xcstrings` gains the new namespaced keys (Decision 10).
    - `Views/_Mockups/` (every file + the directory tree) is removed.
    - `simple-recurring-budgetsTests/Views/AddEditBudgetViewModelTests.swift` and `simple-recurring-budgetsTests/Views/CurrencyPickerTests.swift` are added.
    - `docs/product-features-planning.md` is edited per Decision 14.
2. **No data migration.** Schema is untouched. CloudKit is untouched. `NSUbiquitousKeyValueStore` is untouched.
3. **Rollback strategy.** Revert the single PR. The `_Mockups/` files come back from git history (the user explicitly approved deletion). `RootView` reverts to the placeholder texts. No data loss; no migration to undo.
4. **Smoke test matrix on a clean iPhone simulator** (per `docs/tech-design-doc.md` §5.3):
    - Empty store → toolbar `+` → Add sheet opens with defaults; tap Save with default values → first `Budget` appears in the list.
    - Add sheet → clear name → Save disabled. Type a name, set allocation to 0 → Save still disabled. Set allocation to a positive value → Save enabled.
    - Add sheet → tap currency pill → picker opens; search "Eur" → row filters to EUR; tap row → picker dismisses, parent sheet shows new code.
    - Add sheet → tap each period chip → only one is selected at a time; VoiceOver focus announces "<period> period, selected".
    - Add sheet → toggle Carry-Over off → caption stays visible; Save inserts a `Budget` with `isCarryOverEnabled == false`.
    - Existing budget row → (when F-2.02 lands; for this change verified via `Router.sheet = .editBudget(budget)` in a test or from the preview) → Edit sheet opens pre-filled with the budget's values.
    - Edit sheet → change nothing → Save → `lastModified` unchanged. Change name → Save → `lastModified` is updated.
    - Cancel from any state → no `Budget` is inserted or modified.
    - VoiceOver → all labels and hints announced; chip selection trait announced.
    - Dynamic Type at `xxxLarge` → cards reflow without clipping; chips remain readable.
    - Dark Mode → all backgrounds use named asset colours; nothing reads as a hard-coded white card.

## Open Questions

_(none — every implementation-shape choice is settled in Decisions 1–15. Below are deliberate non-questions:)_

- **VM vs `@State`-only**: settled (Decision 1) — a VM, per §2.1.
- **Allocation type**: settled (Decision 4) — `Decimal`-bound `TextField`.
- **Currency catalog source**: settled (Decision 5) — Foundation; F-3.04 wording is updated.
- **Period chip layout**: settled (Decision 6) — 2×2 grid, hand-rolled chips.
- **Reset Cadence**: explicitly excluded (Goals/Non-Goals) per the PRD and feature-doc PAUSED markers.
- **Save error UX**: explicitly out of scope (Goals/Non-Goals).
- **Future fifth `BudgetPeriod` chip layout**: deliberate non-question (Decision 6) — handled by a future change if/when it happens.
