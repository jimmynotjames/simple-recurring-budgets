## Why

`F-2.03` (Add/Edit Budget screen) is the last placeholder in the primary navigation flow. The `RootView` sheet binding renders bare `Text("Add Budget")` / `Text("Edit Budget")` strings for `SheetRoute.addBudget` and `SheetRoute.editBudget(Budget)`, and `Views/_Mockups/AddEditBudget/` holds three throwaway mockup variants exploring the design. The user has chosen **MockupB · Card Layout** as the production direction.

Shipping this screen unblocks user-driven budget creation and editing (today the only ways a `Budget` enters the store are dev-only `DebugData` seeding and direct `Budget()` calls in tests), turns both `SheetRoute.addBudget` and `SheetRoute.editBudget(Budget)` placeholders into real screens, and lets us delete the entire `_Mockups/` exploration tree (per the file-header instruction: _"DESIGN EXPLORATION — throwaway. Delete the entire `_Mockups/` folder when done."_).

## What Changes

- **Add `Views/AddEditBudgetView.swift`** — a SwiftUI sheet implementing the card-based layout from `MockupB_CardLayout.swift` (Name / Allocation / Period / Carry-Over cards in a `ScrollView`, navigation title `"New Budget"` / `"Edit Budget"`, leading `Cancel`, trailing `Save`). The view is a `View + Services` consumer of an `@Observable` ViewModel (per `docs/tech-design-doc.md` §2.1 escalation criterion #1: the screen holds non-trivial draft/form state not persisted until the user commits).
- **Add `Views/AddEditBudgetViewModel.swift`** — `@Observable final class` owning the form draft (`name`, `allocation: Decimal`, `currencyCode`, `period`, `isCarryOverEnabled`), pure `canSave` validation, and a `save(context:)` method that the view calls at the call-site (per §2.1 VM rules: VM does not store `ModelContext`; `AppSettings` is only passed to `init` because the save body itself does not need it — see Decision 8). Two initialisers: `init(settings:)` for Add mode (defaults from `AppSettings.defaultCarryOverEnabled`, `Locale.current.currency?.identifier ?? "USD"`, `period: .daily`, `allocation: 10`, `name: "Budget"`); `init(editing: Budget)` for Edit mode (seed from the existing `Budget`).
- **Add `Views/CurrencyPickerView.swift`** — searchable, full-catalog ISO-4217 currency picker presented as an inner sheet from the Allocation card. Catalog is sourced **at runtime from Foundation** (`Locale.commonISOCurrencyCodes` → codes; `Locale.current.localizedString(forCurrencyCode:)` → display name) so codes, symbols, and localized names are not hardcoded in our app source. Replaces `MockupShared.CurrencyPickerStub`'s 10-entry hand-curated list.
- **Wire `RootView` sheet binding** — replace the `Text("Add Budget")` and `Text("Edit Budget")` placeholders for `SheetRoute.addBudget` and `SheetRoute.editBudget(Budget)` with the real `AddEditBudgetView`. The `.addExpense` and `.viewExpense` cases keep their placeholders (out of scope here); `.settings` is already wired to the real `SettingsView` (shipped in change `2026-04-28-settings-screen`).
- **Persist on Save** —
    - **Add mode**: build a new `Budget` with the draft values, set `sortOrder = Budget.nextSortOrder(for: context)`, `context.insert(_:)`, `try? context.save()`, dismiss.
    - **Edit mode**: write each draft field back to the passed-in `Budget` only when the value differs (so `lastModified` only bumps if at least one field changed), `try? context.save()`, dismiss.
    - **Cancel**: dismiss without writing. No state survives.
- **Delete the entire `_Mockups/` tree** — `Views/_Mockups/AddEditBudget/MockupA_GroupedForm.swift`, `MockupB_CardLayout.swift`, `MockupC_FlowLayout.swift`, `MockupShared.swift`, plus the empty `_Mockups/` and `AddEditBudget/` directories.
- **Add localized strings to `Resources/Localizable.xcstrings`** — every user-visible label on the new screens uses `String(localized:defaultValue:comment:)` per `docs/tech-design-doc.md` §5.1. New keys cover: navigation titles, Cancel/Save toolbar items, card labels (Name / Allocation / Period / Carry-Over), the carry-over explanatory note, the period chip selection trait, and the currency picker (search field, navigation title, and per-row VoiceOver label).
- **No schema changes.** `Budget` already carries every persisted field this screen edits (`name`, `allocation`, `currencyCode`, `period`, `isCarryOverEnabled`, `sortOrder`). `ResetCadence` remains paused — the screen does NOT surface it; new budgets keep the existing `Budget.init` default of `.never` per `Budget.swift`.
- **Update `docs/product-features-planning.md` F-2.03** — strike the `Carry-over reset cadence` and `monthly → quarterly` bullets' "PAUSED" markers as still in effect (no UI change required by this edit; the bullets stay paused), but flip F-2.03's `**Status:** Open` → `**Status:** Implemented` after this change ships, and add a note that the implementation uses Foundation's system currency catalog rather than a project-owned YAML file (see `F-3.04` note below).
- **Update `docs/product-features-planning.md` F-3.04** — clarify the "stored outside source code" acceptance criterion to accept Foundation's system catalog (`Locale.commonISOCurrencyCodes` / `Locale.localizedString(forCurrencyCode:)`) as a valid source. Mark F-3.04's currency-picker requirements as implemented for the Add/Edit Budget screen; defer any project-owned YAML catalog to a future change only if a need emerges.

## Capabilities

### New Capabilities

- `add-edit-budget-screen`: Behaviour contract for the F-2.03 sheet — fields, defaults, currency picker, carry-over toggle, validation rules, Save / Cancel semantics, Add-vs-Edit modes, persistence flow, and accessibility/localization expectations. Reset Cadence is explicitly out of scope for this capability while the feature is paused per `docs/main-prd.md` §6.7 callout. The capability owns currency-picker requirements that pertain to this screen; it does NOT redefine global currency policy (which lives under F-3.04 in the docs).

### Modified Capabilities

- `app-navigation`: The `RootView` placeholder requirement (`Placeholder destinations are exempt from the no-hard-coded-English rule until replaced`) currently applies to `.addBudget` and `.editBudget(Budget)` among other cases. After this change, those two cases SHALL render the real, fully-localized `AddEditBudgetView` and the i18n exemption SHALL no longer apply to them. The `.addExpense` and `.viewExpense` placeholders remain exempt; `.settings` is already wired to the real `SettingsView` (per change `2026-04-28-settings-screen`) and was already removed from the exemption list.

## Impact

- **New code:**
    - `simple-recurring-budgets/Views/AddEditBudgetView.swift` — the card-based sheet.
    - `simple-recurring-budgets/Views/AddEditBudgetViewModel.swift` — `@Observable` VM with draft state and `save(context:settings:)`.
    - `simple-recurring-budgets/Views/CurrencyPickerView.swift` — searchable Foundation-backed picker.
- **Modified code:**
    - `simple-recurring-budgets/Views/RootView.swift` — replace two `Text(...)` placeholders with the real screen for `.addBudget` and `.editBudget(Budget)`.
    - `simple-recurring-budgets/Resources/Localizable.xcstrings` — new keys for the new screens.
- **Removed code:**
    - `simple-recurring-budgets/Views/_Mockups/AddEditBudget/MockupA_GroupedForm.swift`
    - `simple-recurring-budgets/Views/_Mockups/AddEditBudget/MockupB_CardLayout.swift`
    - `simple-recurring-budgets/Views/_Mockups/AddEditBudget/MockupC_FlowLayout.swift`
    - `simple-recurring-budgets/Views/_Mockups/AddEditBudget/MockupShared.swift`
    - The now-empty `simple-recurring-budgets/Views/_Mockups/AddEditBudget/` and `simple-recurring-budgets/Views/_Mockups/` directories.
- **New tests (Swift Testing):**
    - `simple-recurring-budgetsTests/Views/AddEditBudgetViewModelTests.swift` — Add-mode defaults; Edit-mode seeding; `canSave` cases; Add-mode `save(context:settings:)` inserts a new `Budget` with `sortOrder = nextSortOrder` and the drafted fields; Edit-mode `save(...)` mutates the existing `Budget` and only bumps `lastModified` when at least one field changed; Cancel writes nothing.
    - `simple-recurring-budgetsTests/Views/CurrencyPickerTests.swift` (or equivalent) — code-list source is `Locale.commonISOCurrencyCodes`, sorted; localized name comes from `Locale.localizedString(forCurrencyCode:)`; search filters by both code and localized name.
- **No schema changes.** `Budget` model is untouched. `ResetCadence` enum stays paused. No `VersionedSchema` migration.
- **No CloudKit changes.** No new record types, no new fields, no entitlement edits.
- **No new dependencies.** `Locale`, SwiftUI, and SwiftData carry the entire surface area.
- **Localization / Accessibility:**
    - All new user-visible strings in `Localizable.xcstrings` with `comment:` translator context.
    - VoiceOver labels for the currency button (`"Currency, USD"` plus opens-picker hint), the period chips (`isSelected` trait + per-period label), the allocation field (amount + currency), and the carry-over toggle hint.
    - Dynamic Type: the card layout (per MockupB) uses system text styles and a 2×2 chip grid that does not truncate at `.xxxLarge`.
    - Dark Mode: all surfaces use named asset colours via `appBackground()` and `Color("CellBackground")`; no hard-coded hex.
- **Persistence / Sync:** Save in Add mode performs the canonical `nextSortOrder` → `insert` → `save` sequence used elsewhere in the app (mirrors `DebugData.seed` and `BudgetsViewTests` patterns). Save in Edit mode writes a single `context.save()` for all changed fields. Both flows propagate to CloudKit through the existing pipeline.
- **No new runtime risks beyond standard form-write failures.** `try? context.save()` on Save matches the existing `BudgetsView.move(...)` pattern; user-recoverable error UI is out of scope (no other screen in the app surfaces save errors today).

## Doc alignment

- **Aligned with `docs/main-prd.md`** — PRD §6.7 (carry-over) is respected: the toggle controls only display visibility per budget; the underlying carry-over math (run by `BudgetLifecycleService`) is unchanged. Reset Cadence stays paused. PRD §6.4 (Dynamic Type, VoiceOver) and §6.5 (i18n, per-budget currency) are explicit goals of the new screen.
- **Aligned with `docs/tech-design-doc.md`**:
    - §2.1 (View + Services, ViewModels on demand) — escalation criterion #1 (form draft state not persisted until commit) is the trigger for `AddEditBudgetViewModel`. The grey-area trigger "more than 3 mutable form fields" also applies (we have 5: name, allocation, currency, period, carry-over toggle). Per §2.1 VM rules, the VM stores **draft state and pure logic only**, does NOT hold `ModelContext`, and `save(context:settings:)` takes the context at the call site.
    - §2.2 (Navigation) — the screen is presented via the existing `Router.sheet = .addBudget` / `.editBudget(Budget)` pipeline. No new `SheetRoute` cases.
    - §3.1 / §3.2 (Data model & Over/Under) — no schema changes; Reset Cadence stays at `.never` for new budgets per `Budget.init`.
    - §5.1 (Localization) — every new user-visible string lives in `Localizable.xcstrings` with a `comment:`.
- **Aligned with `docs/ux-design-brief.md`** — "Add/Edit Budget (sheet): Lower-frequency setup — allocation, period, carry-over toggle, ~~reset cadence~~." MockupB matches that brief: a sheet with cards, no streak pressure, system typography, no exclamation marks.
- **Aligned with `docs/product-features-planning.md` F-2.03 (Open)** — every acceptance criterion is satisfied **except** the paused Reset Cadence bullets, which are explicitly excluded by the F-2.03 callout itself.
- **Conflict with `docs/product-features-planning.md` F-3.04 acceptance criterion** — F-3.04 currently says: _"Currency catalog (codes, symbols, localized names) is stored outside source code (e.g. YAML or equivalent)."_ This change ships a Foundation-backed catalog (`Locale.commonISOCurrencyCodes` + `Locale.localizedString(forCurrencyCode:)`) rather than a project-owned YAML file. **Resolution: update the F-3.04 wording** to allow either source ("system-provided via Foundation `Locale`, or a project-owned catalog file when divergence from system behavior is required"). The system source is preferable while no divergence is needed because it tracks ISO-4217 updates as iOS updates without app-side catalog maintenance.
- **Doc updates required after implementation:**
    - `docs/product-features-planning.md` — flip F-2.03 `**Status:** Open` → `**Status:** Implemented`; relax F-3.04's "stored outside source code" wording per the conflict above and mark its currency-picker / picker-language acceptance criteria as implemented for the Add/Edit Budget screen.
    - `docs/tech-design-doc.md` — no architectural change; **no version-history bump expected**. (If implementation surfaces a genuinely new architectural rule it should be captured then; otherwise the existing §2.1 / §3.1 / §5.1 sections cover this work.)
    - `docs/main-prd.md` — no edit (no global constraint changes).
    - `docs/ux-design-brief.md` — no edit (the brief already describes this screen; we are not changing the screen's role).
