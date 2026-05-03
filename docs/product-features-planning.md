# Product Features Planning

**Version:** 0.7  
**Last Updated:** 2026-05-03
**Author/Owner:** Jimmy Ho

For north-star vision, guiding principles, and global constraints, see [main-prd.md](main-prd.md).

### Revision history

| Version | Date       | Author   | Changes |
| ------- | ---------- | -------- | ------- |
| 0.7     | 2026-05-03 | Jimmy Ho | F-3.03 → Ongoing. Translations for all 38 storefront locales now complete and merged; both source-string keying and running `scripts/translate_catalog/` are ongoing concerns per [main-prd.md §6.8](main-prd.md#68-cross-cutting-ongoing-concerns). ACs updated to maintenance checklist. |
| 0.6     | 2026-05-03 | Jimmy Ho | Added Status legend (Open / Partially implemented / Implemented / Ongoing / PAUSED). Updated T-3: F-3.01 and F-3.05 → Ongoing; F-3.02 → Ongoing; F-3.03 description updated to note source-string keying is an ongoing concern per [main-prd.md §6.8](main-prd.md#68-cross-cutting-ongoing-concerns) (F-3.03 split deferred to a separate change). F-8.02 Ongoing-concern sub-bullet added. Cross-cutting concerns governed by [main-prd.md §6.8](main-prd.md#68-cross-cutting-ongoing-concerns). |
| 0.5     | 2026-05-02 | Jimmy Ho | (prior history not recorded) |

---

## Status legend

| Status | Meaning |
|--------|---------|
| `Open` | Not started. |
| `Partially implemented` | Feature has a defined end state but is not fully shipped yet. |
| `Implemented` | Feature has reached its defined end state. |
| `Ongoing` | Cross-cutting concern (see [main-prd.md §6.8](main-prd.md#68-cross-cutting-ongoing-concerns)). Covers every currently shipped surface; every new code change must continue to maintain it. There is no terminal "Implemented" state for these features. |
| `PAUSED` | Explicitly out of scope; retained for future un-pause. |

---

## Themes

### T-1: Technical Foundations

#### Features

##### F-1.01: App Scaffolding

- **Status:** Implemented. Xcode project, test targets, and GitHub repo exist.
- **Description:** Basic app created.
- **Acceptance Criteria:**
  - Xcode project created with main code folder and tests folders scaffolded.
  - git repo created and linked to GitHub
  - Empty app compiles and runs.
- **Edge Cases / Notes:** None
- **Dependencies:** None

##### F-1.02: Data Architecture

- **Status:** Implemented. Implemented by change `data-architecture`; SwiftData models with CloudKit sync are in place.
- **Description:** Database schema created to support entire product roadmap. Persistence uses **SwiftData** with **CloudKit** sync.
- **Acceptance Criteria:**
  - Database schema instantiated in the app.
  - SwiftData models configured for **CloudKit** container sync across the user’s devices.
- **Edge Cases / Notes:** None
- **Dependencies:** None

---

### T-2: Fundamentals

#### Features

##### F-2.01: Budgets screen

- **Status:** Implemented. Implemented by change `budgets-screen` and `finish-budgets-screen`.
- **Description:** Top-level screen: list of Recurring Budget (entity) rows and where the user stands.
- **Acceptance Criteria:**
  - Name of budget field
  - **Remaining for current Budget Period** field — this period’s allocation minus expenses for this period only; **not** merged with carry-over for display (see [main-prd.md §6.7](main-prd.md#67-carry-over-behavior)).
  - **Carry-over** field — separate signed cumulative carryover per [main-prd.md §6.7](main-prd.md#67-carry-over-behavior).
  - **Drag-to-reorder budgets** — user can reorder the list via standard iOS edit-mode drag (and long-press drag where the platform supports it); the order is persisted via `Budget.sortOrder` so it survives app relaunch and syncs across the user's iCloud-paired devices.
  - This **Budgets screen** is the top level of the app.
- **Edge Cases / Notes:** None
- **Dependencies:** None

##### F-2.02: Budget screen

- **Status:** Implemented (excluding F-6.01). Core screen implemented by change `budget-detail-screen`; tap-to-edit on expense rows implemented by change `expense-row-push-navigation`.
- **Description:** Screen that lists Expense Items for a single Budget (entity).
- **Acceptance Criteria:**
  - Shows vertical scrolling list of transactions as a list of most-recent to least-recent.
  - Shows the Budget’s name at top of the screen (navigation title).
  - Shows **Remaining for current Budget Period** and **Carry-over** consistent with [main-prd.md §6.7](main-prd.md#67-carry-over-behavior) and F-2.01.
  - **Status header** — large monospaced remaining amount (deficit-tinted when negative), period label, fuel-gauge `RemainingBar`, and — when carry-over is enabled — an inline `CarryOverChip` and a small **Reset** button for the manual carry-over reset.
  - **Adaptive header layout** — remaining amount and period label render side-by-side below `.xxxLarge` Dynamic Type; stacked vertically at `.xxxLarge` and above. Row spacing scales via `@ScaledMetric`.
  - **Primary Add Expense action** — a full-width `.borderedProminent` button always visible within the screen, presenting `SheetRoute.addExpense(budget)` for this specific budget.
  - **Tap-to-edit expense row** — tapping an expense row pushes `AddEditExpenseView` in Edit mode via `AppRoute.expenseDetail(expense)` (push navigation, standard back-button return). Implemented by change `expense-row-push-navigation`.
  - **Toolbar overflow Menu** (`ellipsis.circle`, top-trailing) hosting:
    - **Edit Budget** — opens the Add/Edit Budget sheet in Edit mode.
    - **Reset Budget…** (destructive) — deletes every `ExpenseItem` for this budget, zeros `carryOverAmount`, and bumps timestamps in a single `ModelContext.save()`. The `Budget` entity itself is **not** deleted. Gated by a confirmation dialog whose body is a single static localized string (no expense count in copy). See [main-prd.md §6.7](main-prd.md#67-carry-over-behavior) for the distinction between Reset Budget, Reset Carry-Over, and Delete Budget.
  - **Reset Carry-over** control with confirmation; clears only this budget’s carry-over (per [main-prd.md §6.7](main-prd.md#67-carry-over-behavior)).
  - **Delete Expense Item** — swipe-to-delete on a row. A full trailing swipe or a tap on the revealed destructive button immediately deletes the expense; no confirmation dialog is presented.
  - **Period-aware expense sections** — expenses are split into a **Current ⟨period⟩** section (items in the current Budget Period, with a section total) and a **Past ⟨period⟩** section (earlier items). Contextual empty captions handle the current-period-empty and zero-expense cases.
  - For each Expense Item, shows the following fields:
    - Date and time (relative: “Today HH:mm” / “Yesterday HH:mm” / locale-aware beyond yesterday)
    - Amount of expense (absolute value; `Color.moneySurplus` tint for add-funds entries per F-6.01 display path)
    - Name of expense (or an italic “Untitled expense” placeholder when nil)
  - **Lifecycle refresh** on task initialization, `scenePhase == .active`, and `onChange(of: budget.expenseItems.count)`.
  - **VoiceOver** — composed accessibility labels on the header (on-budget and over-budget variants) and on each expense row (standard and add-funds variants).
- **Edge Cases / Notes:** The add-funds display path for `ExpenseItem.isAddFunds` is present but no UI to create one exists until F-6.01 (PAUSED).
- **Dependencies:** F-2.01

##### F-2.03: Add/Edit Budget screen

- **Status:** Implemented (excluding paused Reset Cadences). Implemented by change `add-edit-budget-screen`; uses Foundation's system currency catalog (`Locale.commonISOCurrencyCodes` + `Locale.localizedString(forCurrencyCode:)`). Delete Budget implemented by change `delete-budget-button`.
- **Description:** Screen to create or edit a Budget (entity).
- **Acceptance Criteria:**
  - Same screen used to create and edit.
  - Entry point added to **Budgets screen** to create a Budget (entity).
  - Entry point added to **Budget screen** to edit that Budget (entity).
  - **Delete Budget** — Edit mode only. A destructive bordered button appears beneath the form cards when editing an existing budget. Tapping it presents a confirmation dialog with the message "This action cannot be undone." Confirming the dialog deletes the `Budget` and (via the existing `Budget → ExpenseItem` cascade-delete rule) all of its `ExpenseItem` rows in a single `ModelContext.save()`. The sheet is then dismissed and the row disappears reactively from the Budgets list. Add mode does not show this button.
  - Fields:
    - ID: Arbitrary internal identifier, not shown to user. 
    - Name — defaults to empty string (user-editable); the field shows `"Budget"` as a placeholder but the draft value is blank so Save is disabled until the user types a name. In Add mode the Name field auto-focuses (keyboard appears) when the sheet opens.
    - Time Period (daily, weekly, biweekly, monthly). Defaults to daily.
    - Allocation. Defaults to blank (no amount until the user enters one); Save stays disabled until a positive amount is entered. The Allocation card prefixes the numeric field with a currency symbol/code label driven by `AppSettings.currencyDisplay` (symbol / code / code+symbol).
    - **Currency (per budget)** — Each Budget has its own currency. Defaults to locale's currency; USD if unable to determine at all.
    - **Carry-over reset cadence** *(PAUSED — see note below)* — How often cumulative carry-over is cleared **automatically**. Options: **weekly**, **biweekly**, **monthly**, **quarterly**, or **never** (no automatic reset; user uses manual reset only). **Quarterly** and **never** are not Budget Periods; they apply only here. Valid options depend on Budget Period (each cadence must be broader than the period; see [main-prd.md §6.7](main-prd.md#67-carry-over-behavior)). **Defaults** for new budgets: daily → weekly; weekly → monthly; biweekly → quarterly; monthly → quarterly. Scheduled resets align to **period boundaries** (first boundary after the interval), never mid-period.
    - When **Time Period** is **monthly**, the default reset cadence is **quarterly**. Carry-over accumulates across months and resets every quarter. *(PAUSED — see note below.)*

> [!NOTE]
> **PAUSED — Reset Cadences feature is not in scope.** The carry-over reset cadence field and scheduled-reset flow are paused. Acceptance criteria for current work MUST NOT depend on Reset Cadence UI; treat any default as `.never`. Existing description is retained for future reference; **do not include a Reset Cadence control in the Add/Edit Budget sheet while paused.**

- **Edge Cases / Notes:** None
- **Dependencies:** F-2.01

##### F-2.04: Add/Edit/View Expense Item screen

- **Status:** Implemented (changes `add-edit-expense-screen`, `edit-expense-omit-cancel`)
- **Description:** A full screen (or partial screen) that shows all the editable fields of an Expense Item (entity).
- **Acceptance Criteria:**
  - Shows editable name of expense (optional)
  - Shows editable amount of expense (required)
  - Shows date and time (prefilled with current date and time)
  - Same screen is used for add, edit, and view use cases.
  - No Edit Mode. User should be able to edit fields in place without having to toggle modes.
  - **Add mode** shows a leading Cancel button (dismisses without saving) and a trailing Save button.
  - **Edit mode** shows only a trailing Save button; the system back button serves as the discard path.
- **Edge Cases / Notes:**
  - The screen treats Edit and View as a single mode (per the "No Edit Mode" AC); fields are always directly editable without a mode toggle. "View" means opening the Edit sheet for an existing expense.
  - Edit-mode Save preserves the sign of `ExpenseItem.amount`, so existing add-funds rows (F-6.01) survive an edit without flipping to a positive expense. Add mode unconditionally inserts a non-negative amount; the Add Funds toggle UI is part of F-6.01's future change.
  - Omitting Cancel in Edit mode avoids redundancy with the navigation back button and reduces toolbar clutter on the narrow pushed view.
- **Dependencies:** F-2.02

##### F-2.05: Settings screen

- **Status:** Implemented. Implemented by change `settings-screen`.
- **Description:** A modal Settings sheet accessible from the Budgets navigation bar. Contains six sections with functional controls, a Done button, and no ViewModel (plain SwiftUI view).
- **Acceptance Criteria:**
  - A Settings entry-point button is placed in the canonical location in the Budgets navigation bar; tapping it presents a modal sheet.
  - **Budgets section** — Default Carry-Over toggle: bound to `AppSettings.defaultCarryOverEnabled`; see F-2.07 for carry-over semantics.
  - **Calendar section** — Week Starts On picker: shows a confirmation alert before applying the selected weekday; confirmed value writes to `AppSettings.weekStartDay`; see F-5.01 for week-start semantics.
  - **Display section** — Currency Display preference picker: bound to `AppSettings.currencyDisplay`; picker row labels show `"<option label> — <locale-aware example>"` where the example is derived live from `Locale.autoupdatingCurrent` using the canonical `Decimal.formatted(currencyCode:display:locale:)` formatter; value is persisted to `NSUbiquitousKeyValueStore` and applied app-wide to all monetary rendering; see F-3.04 for currency display requirements.
  - **iCloud Sync Status section** — Shows a tri-state row derived from `SyncStatus.rowState`: `.checking` (spinner), `.available` (green checkmark icon, syncing), `.paused` (orange exclamation icon, local-only container despite iCloud sign-in), `.unavailable` (orange x icon, not signed in); section footer appears only for `.unavailable` and `.paused` states; account status is re-queried live on `CKAccountChanged` notifications.
  - **Support section** — "Send Feedback" (opens `mailto:` link), "Rate the App" (invokes `requestReview()`), "Privacy Policy" (opens URL in browser; URL is TBD until launch).
  - **About section** — Displays app version and build number from `CFBundleShortVersionString` / `CFBundleVersion`.
  - Done button dismisses the sheet.
- **Edge Cases / Notes:** `privacyPolicyURL` is intentionally left as a TODO placeholder until the URL is decided before launch.
- **Dependencies:** F-2.01, F-2.07, F-3.04, F-5.01

##### F-2.06: First-run empty state

- **Status:** Implemented. Empty state included in the `budgets-screen` change (ContentUnavailableView with create-budget CTA).
- **Description:** On first launch when the data store contains no budgets, the **Budgets screen** displays a first-run empty state with a clear primary action to create a budget. No placeholder or seed Budget is inserted by the app.
- **Acceptance Criteria:**
  - After first launch with an empty store, the **Budgets screen** shows its empty-state view (title, short description, and a primary "Create a budget" CTA) — NOT a blank or unlabeled screen.
  - No `Budget` entity is created by the app as part of launch; any Budget in the store was created by the user.
  - The empty state is rendered whenever the Budgets `@Query` returns zero rows, so the same view is shown for any future state in which the store transiently presents zero budgets (e.g., during initial CloudKit hydration on a fresh install of an existing iCloud account).
- **Edge Cases / Notes:** The empty-state UI itself ships under F-2.01; F-2.06 is the first-launch contract.
- **Dependencies:** F-2.01

##### F-2.07: Carry-over toggle switch

- **Status:** Implemented. Per-budget toggle implemented as part of the `add-edit-budget-screen` change; global default implemented as part of the Settings screen.
- **Description:** Every budget can have the carry-over calculation turned off. 
- **Acceptance Criteria:**
  - Add/Edit Budget screen has a toggle to turn on/off the carry-over of the prior balances.
  - In Add mode, the carry-over toggle defaults to the current value of the global default carry-over setting in Settings (`AppSettings.defaultCarryOverEnabled`).
  - Settings screen has a global setting to default all new Budgets with carry-over turned on or off. It is turned on by default.
  - This setting is stored in `NSUbiquitousKeyValueStore` and syncs automatically across the user's iCloud-connected devices.
- **Edge Cases / Notes:** None
- **Dependencies:** F-1.02, F-2.02, F-2.05

---

### T-3: Internationalization and Accessibility

#### Features

##### F-3.01: Dynamic Type

- **Status:** Ongoing. All shipped screens use semantic text styles, `@ScaledMetric`, and adaptive layouts. See [main-prd.md §6.8](main-prd.md#68-cross-cutting-ongoing-concerns) for the ongoing-concern rule.
- **Description:** Dynamic Type is supported. This is a cross-cutting ongoing concern — every new UI surface must continue to use semantic text styles and adaptive layouts.
- **Acceptance Criteria (maintenance checklist — applies to every new UI surface):**
  - Semantic system text styles used throughout (`Text`, `Label`, etc. with `.title`, `.body`, `.caption`, etc.); no fixed point sizes.
  - `@ScaledMetric` used for any custom spacing or dimension that should scale with type size.
  - No fixed frame heights that clip text at `.xxxLarge` Dynamic Type or above.
  - Layouts remain usable and readable at `.xxxLarge` accessibility size (sample-tested at least once per major new screen).
- **Edge Cases / Notes:** None
- **Dependencies:** None

##### F-3.02: VoiceOver

- **Status:** Ongoing. All shipped screens audited and remediated under [docs/audits/localization+voiceover-audit-2026-04-30.md](audits/localization+voiceover-audit-2026-04-30.md); pending full interactive walkthrough on hardware. See [main-prd.md §6.8](main-prd.md#68-cross-cutting-ongoing-concerns) for the ongoing-concern rule.
- **Description:** VoiceOver is supported. This is a cross-cutting ongoing concern — every new UI surface must continue to ship with complete VoiceOver support.
- **Acceptance Criteria (maintenance checklist — applies to every new UI surface):**
  - All interactive and informational UI elements carry meaningful `.accessibilityLabel` values.
  - Custom composite views (e.g. carry-over chip, currency picker rows, section headers) collapse to a single VoiceOver element via `.accessibilityElement(children: .ignore)` paired with a composed `.accessibilityLabel(...)`.
  - Section headings on `List` / form screens use `.accessibilityAddTraits(.isHeader)` so the VoiceOver headings rotor surfaces them.
  - Destructive controls (Reset Budget, Reset Carry-Over, Delete Budget, Delete Expense, swipe-to-delete) carry an `.accessibilityHint(...)` describing the irreversible consequence.
  - `swipeActions` are paired with `.accessibilityAction(named:)` mirroring the gesture so VoiceOver users can invoke them via the rotor.
- **Edge Cases / Notes:** Live VoiceOver walkthrough and pseudo-loc smoke procedures are documented in [Appendices B and C of the audit](audits/localization+voiceover-audit-2026-04-30.md); they are delegated to the human verifier on real hardware.
- **Dependencies:** F-3.03

##### F-3.03: Internationalization of text

- **Status:** Ongoing. **English source coverage** is complete and audited under [docs/audits/localization+voiceover-audit-2026-04-30.md](audits/localization+voiceover-audit-2026-04-30.md). **Translations for all 38 App Store storefront locales** (`ar`, `ca`, `cs`, `da`, `de`, `el`, `en-AU`, `en-CA`, `en-GB`, `es`, `es-MX`, `fi`, `fr`, `fr-CA`, `he`, `hi`, `hr`, `hu`, `id`, `it`, `ja`, `ko`, `ms`, `nb`, `nl`, `pl`, `pt-BR`, `pt-PT`, `ro`, `ru`, `sk`, `sv`, `th`, `tr`, `uk`, `vi`, `zh-Hans`, `zh-Hant`) are complete and merged. Both source-string keying and translations are now ongoing maintenance concerns — see [main-prd.md §6.8](main-prd.md#68-cross-cutting-ongoing-concerns).
- **Description:** All user-facing text is keyed and translatable; labels change automatically to match the device's locale. This is a cross-cutting ongoing concern — every new user-facing string added to production views must be keyed immediately AND translations must be produced via the `scripts/translate_catalog/` pipeline before the change ships to users.
- **Acceptance Criteria (maintenance checklist — applies to every new user-facing string):**
  - Every user-facing string in production views uses `Text("key", comment:)` or `String(localized: KEY, defaultValue:, comment:)`; no hard-coded English literals remain.
  - The catalog has no orphan keys and every key carries a translator-friendly `comment:`.
  - All 38 storefront locales have translations for all catalog keys — maintained by re-running `scripts/translate_catalog/` (extract → translate → merge → validate) after any new keys are added.
  - Human pseudo-loc and per-locale spot checks remain part of release verification.
- **Edge Cases / Notes:** Pseudo-localization smoke procedure documented in [Appendix B of the audit](audits/localization+voiceover-audit-2026-04-30.md). Full keying rules in `docs/tech-design-doc.md` §5.1.
- **Dependencies:** None

##### F-3.04: Internationalization of currency

- **Status:** Partially implemented. Per-budget currency picker (`CurrencyPickerView`) and locale-aware formatting shipped with `add-edit-budget-screen`; currency display preference shipped with `settings-screen`. ISO currency display names in the picker come from Foundation (`localizedString(forCurrencyCode:)`) and follow the device locale; any catalog-backed UI copy on that flow is covered by F-3.03.
- **Description:** Currency is **per Budget** (entity) — see **Add/Edit Budget screen** (F-2.03) — not a single global app default. This feature covers formatting, symbols, and the currency catalog used when choosing a Budget’s currency.
- **Acceptance Criteria:**
  - **Add/Edit Budget screen** includes a currency picker; all supported currency codes are available there (not on **Settings screen** as a global override). *(Implemented by `add-edit-budget-screen` change.)*
  - Amounts and symbols in the UI respect **each Budget’s** selected currency and the user’s locale formatting rules.
  - Currency catalog (codes, symbols, localized names) is sourced from outside our application source — either from Foundation’s system catalog (`Locale.commonISOCurrencyCodes` plus `Locale.localizedString(forCurrencyCode:)`) or from a project-owned data file (e.g. YAML) when the app needs to diverge from the system catalog. The Add/Edit Budget screen ships the system-catalog path.
  - The display name of each currency in the picker is internationalized. *(Implemented by `add-edit-budget-screen` change.)*
- **Edge Cases / Notes:** None
- **Dependencies:** F-2.03, F-3.03

##### F-3.05: Dark Mode

- **Status:** Ongoing. Named color assets with light/dark appearances used on all shipped screens; semantic system colors throughout. See [main-prd.md §6.8](main-prd.md#68-cross-cutting-ongoing-concerns) for the ongoing-concern rule.
- **Description:** Dark Mode is supported. This is a cross-cutting ongoing concern — every new UI surface must continue to use named color assets with separate light/dark appearances, never hard-coded color literals.
- **Acceptance Criteria (maintenance checklist — applies to every new UI surface):**
  - Named color assets from `Resources/Assets.xcassets` with separate light/dark appearances used for all custom colors (see `docs/tech-design-doc.md` §5.5 for the color asset table and `appBackground()` modifier pattern).
  - Semantic system colors used throughout; no hard-coded color literals.
  - Exceptions: `Color.moneySurplus` / `Color.moneyDeficit` (defined in `Views/Color+Money.swift`), iCloud sync-status system colors, and `.tint(.red)` for destructive controls are permitted system-palette exceptions per `docs/tech-design-doc.md` §5.5.
- **Edge Cases / Notes:** None
- **Dependencies:** None

---

### T-4: Cute Shit

#### Features

##### F-4.01: Technical - Refactor support multiple color themes.

- **Status:** Open
- **Description:** 
- **Acceptance Criteria:**
- **Edge Cases / Notes:**
- **Dependencies:**

##### F-4.02: Support multiple color themes

- **Status:** Open
- **Description: For example, feminine, masculine, dogs, cats, whatever.** 
- **Acceptance Criteria:**
- **Edge Cases / Notes:**
- **Dependencies:**

##### F-4.03: Support an icon for each Budget

- **Status:** Open
- **Description: User can pick an icon to help distinguish each Budget**
- **Acceptance Criteria:**
  - **Add/Edit Budget screen** includes icon selection for each Budget (entity).
  - **Budget screen** and **Budgets screen** display the icon where applicable.
  - If feasible, use LLM to guess default icon for each Budget.
  - User can pick emoji
  - If feasible, user can pick from Apple-native emoji-like icons that can be custom-generated.
- **Edge Cases / Notes:**
- **Dependencies:**

##### F-4.04: Support for photo upload for icon for each Budget

- **Status:** Open
- **Description:** 
- **Acceptance Criteria:**
- **Edge Cases / Notes:**
- **Dependencies:**

---

### T-5: Configurations

#### Features

##### F-5.01: Configurable start of week.

- **Status:** Implemented. `AppSettings.weekStartDay` with Settings picker and confirmation alert; implemented by change `settings-screen`.
- **Description:** Choose start day of week for weekly Budgets.
- **Acceptance Criteria:**
  - Default value is determined by locale's official week starting day. For example, Sunday in the USA, Monday in most of Europe. 
  - Configurable to be different. Will cascade to all existing Budgets. 
  - Display pop-up to acknowledge that existing Budgets will be affected.
  - This setting is stored in `NSUbiquitousKeyValueStore` and syncs automatically across the user's iCloud-connected devices.
- **Edge Cases / Notes:**
- **Dependencies:**

---

### T-6: Miscellaneous

#### Features

##### F-6.01: Allow manually adding funds

- **Status:** Partially implemented. Model layer done (`isAddFunds`, `displayAmount` on `ExpenseItem`, negative-amount convention, edit sign preservation in `AddEditExpenseViewModel`). Budget detail screen shows add-funds rows with `Color.moneySurplus` tint and VoiceOver labels. UI toggle on the Add Expense screen to *create* an add-funds entry is not yet shipped.
- **Description:** User can add a transaction where the amount adds to available funds instead of subtract from it. 
- **Acceptance Criteria:**
- **Edge Cases / Notes:**
- **Dependencies:**

##### F-6.02: Expense Type on Expense Items

- **Status:** Partially implemented. Schema done: `expenseType: String?` on `ExpenseItem` (persisted in SchemaV1). No user-facing editor shipped yet.
- **Description:** 
  - On each Expense Item, allow user to specify an Expense Type.  
  - User can select from "Cash", "Credit Card", "Debit Card", but can also choose to type in their own value.
  - If user types in own value, that is stored as a predefined value in the future.
- **Acceptance Criteria:**
- **Edge Cases / Notes:**
- **Dependencies:**

##### F-6.03: App Store rating prompt

- **Status:** Open
- **Description:** Prompt the user to rate the app in the App Store after meaningful product use and/or after a minimum elapsed time period.
- **Acceptance Criteria:**
  - The app requests an App Store rating only after eligibility conditions are met, based on meaningful usage and/or elapsed time.
  - Eligibility thresholds and exact trigger formula are explicitly **TBD** and will be finalized later.
  - Prompting behavior is respectful and non-intrusive (not shown too frequently, and not shown on every launch).
  - The app tracks prompt outcomes so a recent dismissal or rating action prevents immediate re-prompting.
- **Edge Cases / Notes:** Final trigger logic, cooldown duration, and definition of "meaningful usage" are **TBD**.
- **Dependencies:** None

---

### T-7: Optimizing the UX

#### Features

##### F-7.01: Receipt scanning via camera

- **Status:** Open
- **Description:** User takes a photo of a receipt; on-device machine vision extracts the amount (and optionally merchant name / date) to pre-fill an Expense Item.
- **Acceptance Criteria:**
- **Edge Cases / Notes:**
- **Dependencies:** F-2.04

##### F-7.02: Voice input to add an Expense Item

- **Status:** Open
- **Description:** User speaks via Siri and/or in-app voice input; Apple's on-device NLP parses the utterance into an Expense Item (amount, name, date/time).
- **Acceptance Criteria:**
- **Edge Cases / Notes:**
- **Dependencies:** F-2.04

##### F-7.03: Voice query for Budget status

- **Status:** Open
- **Description:** User speaks via Siri and/or in-app voice input to ask about a Budget's current status; the app responds with the **Remaining for current Budget Period** amount and the separate **Carry-over** amount.
- **Acceptance Criteria:**
- **Edge Cases / Notes:**
- **Dependencies:** F-2.01, F-2.02

##### F-7.04: Recently used expenses

- **Status:** Open
- **Description:** Surface the user's recently logged expenses as tappable suggestions when adding a new Expense Item, so they can reuse a prior entry (name, amount) with one tap.
- **Acceptance Criteria:**
- **Edge Cases / Notes:**
- **Dependencies:** F-2.04

##### F-7.05: Per-budget period start date

- **Status:** Open
- **Description:** Allow each Budget to have its own period start date. For weekly and biweekly Budgets, the user can also select the start day of the cycle in addition to when to start the budget; for monthly Budgets, the user selects the start day of the month. The default is to start the budget today.
- **Acceptance Criteria:**
- **Edge Cases / Notes:**
- **Dependencies:** F-2.03

##### F-7.06: Stop a Budget

- **Status:** Open
- **Description:** User can stop a Budget, halting all period calculations and carry-over accumulation until they choose to resume it. A stopped Budget remains visible but is clearly marked as inactive.
- **Acceptance Criteria:**
- **Edge Cases / Notes:**
- **Dependencies:** F-2.01, F-2.02, F-2.03

---

### T-8: Analytics and Observability

#### Features

##### F-8.01: Diagnostic logging via OSLog

- **Status:** Implemented. Implemented by change `oslog-diagnostic-logging`.
- **Description:** All operational / diagnostic events (container bootstrap, CloudKit sync outcomes, UI traces) are written directly via `OSLog.Logger` constants in [`Logging/AppLoggers.swift`](../simple-recurring-budgets/Logging/AppLoggers.swift). Diagnostic logging never passes through `AnalyticsClient`, which is product-only. Categories are fixed: `bootstrap`, `cloudkit`, `ui` (defined in `AppLoggers.swift`).
- **Acceptance Criteria:**
  - **Bootstrap category** (`Logger.bootstrap`): a single `info`-level entry on app launch indicating the resolved `AppDatabaseLaunchMode` (Release builds always log `.normal`; DEBUG logs the active case from the dev override).
  - **CloudKit category** (`Logger.cloudKit`): retain the existing three call sites in `makeProductionModelContainer` (`cloudkit.container.backed` / `localFallback` / `localSuccess` / `failed`); add an entry on `CKAccountChanged` notification reception in `SettingsView` that records the old → new account status transition for the iCloud sync row (privacy: `.public` for the enum value, never the user's identity).
  - **UI category** (`Logger.ui`): one `debug`-level entry per user-initiated destructive action (`Reset Budget`, `Reset Carry-Over`, `Delete Budget`, `Delete Expense`) recording the entity's `persistentModelID` (privacy: `.private`) and the action name. No entries for non-destructive UI traces in Phase 1 — leaner logging by default; add new entries only when justified by a debugging need.
  - **Boundary contract**: no call site under `simple-recurring-budgets/` invokes both `Logger.*` and `AnalyticsClient.track(...)` for the same conceptual event with the intent of cross-routing. (A single user action MAY produce one of each — e.g. a successful Add Expense fires `expense_logged` to Mixpanel **and** writes a `Logger.ui` entry — but the two calls are independent and the `AnalyticsClient` call is never derived from a `Logger` callback or vice versa.)
  - **Privacy levels**: every `Logger.*` call site that interpolates a value MUST set an explicit `privacy:` argument. Strings derived from user input or model identifiers default to `.private`; static enum values, error descriptions from Apple frameworks, and bundle metadata may be `.public`.
- **Edge Cases / Notes:** This feature is the OSLog half of the F-8.01 / F-8.02 split documented in [analytics-spec.md §17](analytics-spec.md#17-boundary-with-f-801-oslog). It SHOULD ship as its own OpenSpec change before F-8.02 so the boundary is established before any Mixpanel call site is added.
- **Dependencies:** None

##### F-8.02: Mixpanel Phase 1 — foundation and basic stats

- **Status:** Implemented (change `mixpanel-phase-1-foundation`, 2026-05-03). **Ongoing concern** — the event surface must be maintained with every code change; see note below.
- **Description:** Establish the product analytics foundation. Phase 1 is the smallest viable Mixpanel integration that still answers the most fundamental questions about who is using the app, what they are using it for, and whether they come back — and that informs how we develop future features. Detailed events, properties, dashboards, identity, consent jurisdictions, and architecture live in [analytics-spec.md](analytics-spec.md). Mixpanel is the chosen vendor; rationale and weaknesses we sidestep are in spec §1 (Vendor Choice).
  - **Ongoing concern ([main-prd.md §6.8](main-prd.md#68-cross-cutting-ongoing-concerns)):** Every new user-initiated action that materially changes app state (new destructive action, new screen with a primary CTA, new toggle whose value affects retention or feature usage) MUST ship with the corresponding `AnalyticsClient.track(...)` event per [analytics-spec.md](analytics-spec.md). No PII; respect consent. This applies to every change going forward — not only to Phase 1 or Phase 2 milestones.
- **Acceptance Criteria:**
  - **Constraints:** see [analytics-spec.md §2 (Canonical Constraints)](analytics-spec.md#2-canonical-constraints). That section is the single source of truth for the locale-aware consent default, no-PII guarantee, OSLog boundary, copy-keying, and lazy-SDK-init rules that gate this feature.
  - **Product questions Phase 1 must be able to answer:** see [analytics-spec.md §3 (Product Questions — Phase 1)](analytics-spec.md#3-product-questions--phase-1) for the canonical list, and [§11 (Phase 1 Dashboards)](analytics-spec.md#11-phase-1-dashboards) for the report each question lands on. Phase 1 ships only when each question in §3 has a corresponding dashboard or report in §11.
  - **Deliverables (the spec is the source of truth):**
    - Mixpanel SDK integrated, opt-in toggle in Settings, first-run consent sheet in consent-required jurisdictions, and the canonical event + property surface implemented per [analytics-spec.md](analytics-spec.md).
    - Phase 1 dashboards built and linked from the spec.
    - Companion updates to [tech-design-doc.md](tech-design-doc.md) §§4.5, 7, 9 per spec §19.
- **Edge Cases / Notes:**
  - Mixpanel is **not** a crash reporter or time-series telemetry log; crash and lifecycle data stays on `OSLog` (F-8.01) and Apple-native frameworks (MetricKit). The full F-8.01 boundary is in [analytics-spec.md](analytics-spec.md) §17.
  - Final per-event property list, super properties, people properties, and dashboards live in [analytics-spec.md](analytics-spec.md). Treat that doc as the implementation contract; this entry is intentionally high-level.
  - **Historical implementation starting state.** Pre-F-8.02 scaffolding refactors are recorded in [analytics-spec.md §16.1](analytics-spec.md#161-implementation-starting-state-codebase-snapshot-historical-record) (now a historical record). All refactors are complete.
- **Dependencies:** F-2.05 (Settings — for the opt-in toggle), F-3.03 (i18n of consent + Settings copy), F-8.01 (OSLog boundary; SHOULD ship before F-8.02)

##### F-8.03: Mixpanel Phase 2 — reactive deepening and experimentation seam

- **Status:** Open
- **Description:** React to what Phase 1 reveals. Add the behavioral analysis depth Phase 1 cannot deliver — funnel drop-offs, cohort retention, and whether the app's UX promises (notably "fast logging") are materializing in practice — and add a controlled experimentation seam so future small UX experiments (theme defaults, rating-prompt thresholds, copy variants) can run without app updates. The detailed event / property / dashboard surface lives in [analytics-spec.md](analytics-spec.md) §§4, 12–15, and MUST be re-validated against actual Phase 1 evidence before implementation: low-signal Phase 2 properties are dropped or replaced.
- **Acceptance Criteria:**
  - **Constraints:** see [analytics-spec.md §2 (Canonical Constraints)](analytics-spec.md#2-canonical-constraints), sections 2.1 and 2.2. All Phase 1 constraints carry forward unchanged; §2.2 adds the Phase-2-specific feature-flag constraints (pull-only, cached, never blocking launch).
  - **Product questions Phase 2 should answer:** see [analytics-spec.md §4 (Product Questions — Phase 2)](analytics-spec.md#4-product-questions--phase-2) for the canonical list, and [§14 (Phase 2 Dashboards)](analytics-spec.md#14-phase-2-dashboards-planned) for the report each question lands on. Per the spec, Phase 2 scope is re-validated against actual Phase 1 evidence before implementation; low-signal Phase 2 items are dropped or replaced.
  - **Deliverables (the spec is the source of truth):**
    - Funnel-abandonment events, cohort-driving people properties, and lightweight performance properties implemented per [analytics-spec.md](analytics-spec.md) §§12–14.
    - `FeatureFlagClient` protocol + `MixpanelFeatureFlagClient` and `StaticFeatureFlagClient` implementations per spec §15.
    - Phase 2 dashboards built and linked from the spec.
    - The implementing change cites Phase 1 dashboard evidence motivating (or trimming) each Phase 2 property and event before scope is locked.
- **Edge Cases / Notes:**
  - Phase 2 acceptance criteria are written before Phase 1 evidence exists; the spec's Phase 2 lists are intentionally marked **planned** and may shift.
- **Dependencies:** F-8.02

